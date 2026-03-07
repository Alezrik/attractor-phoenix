defmodule AttractorEx.ModelStylesheet do
  @moduledoc false

  @type rule :: %{selector: String.t(), attrs: map(), rank: integer(), order: integer()}

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
      case normalize_rule(selector, attrs, index) do
        nil -> acc
        rule -> [rule | acc]
      end
    end)
    |> Enum.reverse()
  end

  defp list_to_rules(list) do
    list
    |> Enum.with_index()
    |> Enum.reduce([], fn {item, index}, acc ->
      rule =
        case item do
          %{"selector" => selector, "attrs" => attrs} -> normalize_rule(selector, attrs, index)
          %{selector: selector, attrs: attrs} -> normalize_rule(selector, attrs, index)
          _ -> nil
        end

      case rule do
        nil -> acc
        value -> [value | acc]
      end
    end)
    |> Enum.reverse()
  end

  defp normalize_rule(selector, attrs, index) when is_binary(selector) and is_map(attrs) do
    normalized_selector = String.trim(selector)

    if normalized_selector == "" do
      nil
    else
      %{
        selector: normalized_selector,
        attrs: stringify_keys(attrs),
        rank: selector_rank(normalized_selector),
        order: index
      }
    end
  end

  defp normalize_rule(_selector, _attrs, _index), do: nil

  defp stringify_keys(map) do
    map
    |> Enum.map(fn {k, v} -> {to_string(k), v} end)
    |> Map.new()
  end

  defp selector_rank("*"), do: 0
  defp selector_rank("node"), do: 0
  defp selector_rank("node[*]"), do: 0

  defp selector_rank(selector) when is_binary(selector) do
    cond do
      String.starts_with?(selector, "#") -> 3
      String.starts_with?(selector, ".") -> 2
      String.starts_with?(selector, "node.") -> 2
      String.starts_with?(selector, "type=") -> 1
      String.starts_with?(selector, "node[type=") -> 1
      true -> 0
    end
  end

  defp selector_match?("*", _node_id, _type, _classes), do: true
  defp selector_match?("node", _node_id, _type, _classes), do: true
  defp selector_match?("node[*]", _node_id, _type, _classes), do: true

  defp selector_match?(<<"#", id::binary>>, node_id, _type, _classes), do: id == node_id

  defp selector_match?(<<"node.", class_name::binary>>, _node_id, _type, classes),
    do: class_name in classes

  defp selector_match?(<<".", class_name::binary>>, _node_id, _type, classes),
    do: class_name in classes

  defp selector_match?(<<"type=", expected::binary>>, _node_id, type, _classes),
    do: expected == type

  defp selector_match?(selector, _node_id, type, _classes) do
    case Regex.run(~r/^node\[type=(.+)\]$/, selector, capture: :all_but_first) do
      [expected] -> expected == type
      _ -> false
    end
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
