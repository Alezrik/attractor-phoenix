defmodule AttractorEx.ModelStylesheet do
  @moduledoc false

  @type rule :: %{selector: String.t(), attrs: map(), rank: integer(), order: integer()}
  @selector_ident ~r/^[A-Za-z_][A-Za-z0-9_\-]*$/

  def parse(nil), do: {:ok, []}
  def parse(%{} = stylesheet), do: {:ok, map_to_rules(stylesheet)}
  def parse(stylesheet) when is_list(stylesheet), do: {:ok, list_to_rules(stylesheet)}

  def parse(stylesheet) when is_binary(stylesheet) do
    trimmed = String.trim(stylesheet)

    if trimmed == "" do
      {:ok, []}
    else
      decode_json_stylesheet(trimmed)
    end
  end

  def parse(_), do: {:error, "model_stylesheet must be a JSON object, JSON array, or map"}

  def attrs_for_node(rules, node_id, node_attrs) when is_list(rules) do
    classes = class_tokens(Map.get(node_attrs, "class"))

    type =
      Map.get(node_attrs, "type") || AttractorEx.Node.handler_type_for_shape(node_attrs["shape"])

    rules
    |> Enum.filter(&selector_match?(&1.selector, node_id, type, classes))
    |> Enum.sort_by(fn rule -> {rule.rank, rule.order} end)
    |> Enum.reduce(%{}, fn rule, acc -> Map.merge(acc, rule.attrs) end)
  end

  defp decode_json_stylesheet(trimmed) do
    case Jason.decode(trimmed) do
      {:ok, %{} = map} ->
        {:ok, map_to_rules(map)}

      {:ok, list} when is_list(list) ->
        {:ok, list_to_rules(list)}

      {:ok, _other} ->
        {:error, "model_stylesheet JSON must decode to an object or array"}

      {:error, _reason} ->
        {:error, "model_stylesheet is not valid JSON"}
    end
  end

  defp map_to_rules(map) do
    map
    |> Enum.with_index()
    |> Enum.reduce([], fn {{selector, attrs}, index}, acc ->
      normalize_rules(selector, attrs, index) ++ acc
    end)
    |> Enum.reverse()
  end

  defp list_to_rules(list) do
    list
    |> Enum.with_index()
    |> Enum.reduce([], fn {item, index}, acc ->
      rules =
        case item do
          %{"selector" => selector, "attrs" => attrs} -> normalize_rules(selector, attrs, index)
          %{selector: selector, attrs: attrs} -> normalize_rules(selector, attrs, index)
          _ -> []
        end

      rules ++ acc
    end)
    |> Enum.reverse()
  end

  defp normalize_rules(selector, attrs, index) when is_binary(selector) and is_map(attrs) do
    attrs = stringify_keys(attrs)

    selector
    |> split_selector_list()
    |> Enum.with_index()
    |> Enum.reduce([], fn {raw_selector, selector_offset}, acc ->
      normalized_selector = String.trim(raw_selector)

      case parse_selector(normalized_selector) do
        {:ok, _parsed, rank} ->
          [
            %{
              selector: normalized_selector,
              attrs: attrs,
              rank: rank,
              order: index * 1_000 + selector_offset
            }
            | acc
          ]

        :error ->
          acc
      end
    end)
  end

  defp normalize_rules(_selector, _attrs, _index), do: []

  defp stringify_keys(map) do
    map
    |> Enum.map(fn {k, v} -> {to_string(k), v} end)
    |> Map.new()
  end

  defp selector_match?(selector, node_id, type, classes) do
    case parse_selector(selector) do
      {:ok, parsed, _rank} ->
        selector_matches_parsed?(parsed, node_id, type, classes)

      :error ->
        false
    end
  end

  defp selector_matches_parsed?(%{all_nodes?: true}, _node_id, _type, _classes), do: true

  defp selector_matches_parsed?(parsed, node_id, type, classes) do
    id_match? = is_nil(parsed.id) or parsed.id == node_id
    type_match? = is_nil(parsed.type) or parsed.type == type
    class_match? = Enum.all?(parsed.classes, &(&1 in classes))
    id_match? and type_match? and class_match?
  end

  defp parse_selector("*"), do: {:ok, %{all_nodes?: true, id: nil, type: nil, classes: []}, 0}
  defp parse_selector("node"), do: {:ok, %{all_nodes?: true, id: nil, type: nil, classes: []}, 0}

  defp parse_selector("node[*]"),
    do: {:ok, %{all_nodes?: true, id: nil, type: nil, classes: []}, 0}

  defp parse_selector(selector) when is_binary(selector) do
    trimmed = String.trim(selector)

    rest =
      if String.starts_with?(trimmed, "node") do
        String.slice(trimmed, 4..-1//1)
      else
        trimmed
      end

    parse_selector_tokens(rest, %{all_nodes?: false, id: nil, type: nil, classes: []})
  end

  defp parse_selector_tokens("", parsed), do: {:ok, parsed, selector_specificity(parsed)}

  defp parse_selector_tokens(rest, parsed) do
    cond do
      String.starts_with?(rest, "[type=") ->
        parse_bracket_type_selector(rest, parsed)

      String.starts_with?(rest, "type=") ->
        parse_bare_type_selector(rest, parsed)

      String.starts_with?(rest, "#") ->
        parse_id_selector(rest, parsed)

      String.starts_with?(rest, ".") ->
        parse_class_selector(rest, parsed)

      true ->
        :error
    end
  end

  defp parse_bracket_type_selector(rest, parsed) do
    case Regex.run(~r/^\[type=([^\]]+)\](.*)$/, rest, capture: :all_but_first) do
      [raw_type, remaining] ->
        with {:ok, type} <- normalize_type_token(raw_type),
             :ok <- ensure_single_type(parsed.type) do
          parse_selector_tokens(remaining, %{parsed | type: type})
        else
          _ -> :error
        end

      _ ->
        :error
    end
  end

  defp parse_bare_type_selector(rest, parsed) do
    case Regex.run(~r/^type=([A-Za-z_][A-Za-z0-9_\-]*|\"[^\"]+\")(.*)$/, rest,
           capture: :all_but_first
         ) do
      [raw_type, remaining] ->
        with {:ok, type} <- normalize_type_token(raw_type),
             :ok <- ensure_single_type(parsed.type) do
          parse_selector_tokens(remaining, %{parsed | type: type})
        else
          _ -> :error
        end

      _ ->
        :error
    end
  end

  defp parse_id_selector(rest, parsed) do
    case Regex.run(~r/^#([A-Za-z_][A-Za-z0-9_\-]*)(.*)$/, rest, capture: :all_but_first) do
      [id, remaining] ->
        if is_nil(parsed.id) do
          parse_selector_tokens(remaining, %{parsed | id: id})
        else
          :error
        end

      _ ->
        :error
    end
  end

  defp parse_class_selector(rest, parsed) do
    case Regex.run(~r/^\.([A-Za-z_][A-Za-z0-9_\-]*)(.*)$/, rest, capture: :all_but_first) do
      [class_name, remaining] ->
        parse_selector_tokens(remaining, %{parsed | classes: parsed.classes ++ [class_name]})

      _ ->
        :error
    end
  end

  defp normalize_type_token(raw_type) do
    type =
      raw_type
      |> String.trim()
      |> String.trim_leading("\"")
      |> String.trim_trailing("\"")

    if Regex.match?(@selector_ident, type) do
      {:ok, type}
    else
      :error
    end
  end

  defp ensure_single_type(nil), do: :ok
  defp ensure_single_type(_), do: :error

  defp selector_specificity(parsed) do
    id_score = if is_nil(parsed.id), do: 0, else: 100
    class_score = length(parsed.classes) * 10
    type_score = if is_nil(parsed.type), do: 0, else: 1
    id_score + class_score + type_score
  end

  defp split_selector_list(text) do
    {parts, current, _in_quotes, _bracket_depth} =
      text
      |> String.graphemes()
      |> Enum.reduce({[], "", false, 0}, fn char, {parts, current, in_quotes, bracket_depth} ->
        cond do
          char == "\"" ->
            {parts, current <> char, not in_quotes, bracket_depth}

          char == "[" and not in_quotes ->
            {parts, current <> char, in_quotes, bracket_depth + 1}

          char == "]" and not in_quotes and bracket_depth > 0 ->
            {parts, current <> char, in_quotes, bracket_depth - 1}

          char == "," and not in_quotes and bracket_depth == 0 ->
            {[current | parts], "", in_quotes, bracket_depth}

          true ->
            {parts, current <> char, in_quotes, bracket_depth}
        end
      end)

    [current | parts]
    |> Enum.reverse()
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp class_tokens(nil), do: []

  defp class_tokens(value) do
    value
    |> to_string()
    |> String.split(~r/[,\s]+/, trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end
end
