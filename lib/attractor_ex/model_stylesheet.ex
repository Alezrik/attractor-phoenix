defmodule AttractorEx.ModelStylesheet do
  @moduledoc false

  @type rule :: %{selector: String.t(), attrs: map(), rank: integer(), order: integer()}
  @type lint_diagnostic :: %{severity: :warning, code: atom(), message: String.t(), node_id: nil}
  @selector_ident ~r/^[A-Za-z_][A-Za-z0-9_\.\-]*$/
  @supported_css_properties [
    "allow_partial",
    "class",
    "command",
    "fidelity",
    "goal_gate",
    "human.default_choice",
    "human.input",
    "human.multiple",
    "human.required",
    "human.timeout",
    "join_policy",
    "k",
    "llm_model",
    "llm_provider",
    "label",
    "manager.actions",
    "manager.max_cycles",
    "manager.poll_interval",
    "manager.stop_condition",
    "max_parallel",
    "max_retries",
    "reasoning_effort",
    "retry_target",
    "fallback_retry_target",
    "prompt",
    "quorum_ratio",
    "shape",
    "stack.child_autostart",
    "stack.child_dotfile",
    "temperature",
    "timeout",
    "tool_command",
    "type",
    "max_tokens",
    "model"
  ]

  def parse(nil), do: {:ok, []}
  def parse(%{} = stylesheet), do: {:ok, map_to_rules(stylesheet)}
  def parse(stylesheet) when is_list(stylesheet), do: {:ok, list_to_rules(stylesheet)}

  def parse(stylesheet) when is_binary(stylesheet) do
    trimmed = stylesheet |> strip_css_comments() |> String.trim()

    if trimmed == "" do
      {:ok, []}
    else
      decode_json_stylesheet(trimmed)
    end
  end

  def parse(_), do: {:error, "model_stylesheet must be a JSON object, JSON array, or map"}

  def lint(nil), do: []

  def lint(stylesheet) when is_map(stylesheet) do
    stylesheet
    |> Enum.reduce([], fn {selector, attrs}, acc ->
      acc
      |> maybe_add_invalid_selector_diag(selector)
      |> maybe_add_invalid_rule_attrs_diag(selector, attrs)
    end)
    |> Enum.reverse()
  end

  def lint(stylesheet) when is_list(stylesheet) do
    stylesheet
    |> Enum.with_index()
    |> Enum.reduce([], fn {item, index}, acc ->
      case item do
        %{"selector" => selector, "attrs" => attrs} when is_map(attrs) ->
          maybe_add_invalid_selector_diag(acc, selector)

        %{selector: selector, attrs: attrs} when is_map(attrs) ->
          maybe_add_invalid_selector_diag(acc, selector)

        _ ->
          [
            lint_diag(
              :model_stylesheet_rule_invalid,
              "model_stylesheet rule at index #{index} is invalid and will be ignored."
            )
            | acc
          ]
      end
    end)
    |> Enum.reverse()
  end

  def lint(stylesheet) when is_binary(stylesheet) do
    trimmed = stylesheet |> strip_css_comments() |> String.trim()

    cond do
      trimmed == "" ->
        []

      true ->
        case Jason.decode(trimmed) do
          {:ok, %{} = map} ->
            lint(map)

          {:ok, list} when is_list(list) ->
            lint(list)

          _ ->
            lint_css_stylesheet(trimmed)
        end
    end
  end

  def lint(_), do: []

  def attrs_for_node(rules, node_id, node_attrs) when is_list(rules) do
    classes = class_tokens(Map.get(node_attrs, "class"))
    shape = Map.get(node_attrs, "shape") |> to_string() |> String.trim()

    type =
      Map.get(node_attrs, "type") || AttractorEx.Node.handler_type_for_shape(node_attrs["shape"])

    rules
    |> Enum.filter(&selector_match?(&1.selector, node_id, type, shape, classes))
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
        parse_css_stylesheet(trimmed)

      {:error, _reason} ->
        parse_css_stylesheet(trimmed)
    end
  end

  defp parse_css_stylesheet(stylesheet) do
    stylesheet
    |> parse_css_rules([], 0)
    |> case do
      {:ok, rules} -> {:ok, rules}
      _ -> {:error, "model_stylesheet is not valid JSON or CSS stylesheet"}
    end
  end

  defp parse_css_rules(remaining, rules, index) do
    trimmed = String.trim(remaining)

    if trimmed == "" do
      {:ok, Enum.reverse(rules)}
    else
      case take_css_rule(trimmed) do
        {:ok, selector, declarations_text, next} ->
          attrs = parse_css_declarations(declarations_text)
          normalized = normalize_rules(selector, attrs, index)
          parse_css_rules(next, Enum.reverse(normalized) ++ rules, index + 1)

        :error ->
          :error
      end
    end
  end

  defp parse_css_declarations(text) do
    text
    |> split_css_declarations()
    |> Enum.map(&String.trim/1)
    |> Enum.reduce(%{}, fn declaration, acc ->
      case String.split(declaration, ":", parts: 2) do
        [property, value] ->
          maybe_put_css_declaration(acc, property, value)

        _ ->
          case String.split(declaration, "=", parts: 2) do
            [property, value] -> maybe_put_css_declaration(acc, property, value)
            _ -> acc
          end
      end
    end)
  end

  defp recognized_css_property?(property) do
    property in @supported_css_properties
  end

  defp trim_wrapping_quotes(value) do
    trimmed = String.trim(value)

    case trimmed do
      <<quote, rest::binary>> when quote in [?", ?'] ->
        closing = <<quote>>

        if String.ends_with?(rest, closing) do
          rest
          |> binary_part(0, byte_size(rest) - 1)
          |> unescape_string()
        else
          trimmed
        end

      _ ->
        trimmed
    end
  end

  defp unescape_string(value) do
    value
    |> String.replace("\\n", "\n")
    |> String.replace("\\r", "\r")
    |> String.replace("\\t", "\t")
    |> String.replace("\\\"", "\"")
    |> String.replace("\\'", "'")
    |> String.replace("\\\\", "\\")
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

  defp selector_match?(selector, node_id, type, shape, classes) do
    case parse_selector(selector) do
      {:ok, parsed, _rank} ->
        selector_matches_parsed?(parsed, node_id, type, shape, classes)

      :error ->
        false
    end
  end

  defp selector_matches_parsed?(%{all_nodes?: true}, _node_id, _type, _shape, _classes), do: true

  defp selector_matches_parsed?(parsed, node_id, type, shape, classes) do
    id_match? = is_nil(parsed.id) or parsed.id == node_id
    type_match? = is_nil(parsed.type) or parsed.type == type
    shape_match? = is_nil(parsed.shape) or parsed.shape == shape
    class_match? = Enum.all?(parsed.classes, &(&1 in classes))
    id_match? and type_match? and shape_match? and class_match?
  end

  defp parse_selector("*"),
    do: {:ok, %{all_nodes?: true, id: nil, type: nil, shape: nil, classes: []}, 0}

  defp parse_selector("node"),
    do: {:ok, %{all_nodes?: true, id: nil, type: nil, shape: nil, classes: []}, 0}

  defp parse_selector("node[*]"),
    do: {:ok, %{all_nodes?: true, id: nil, type: nil, shape: nil, classes: []}, 0}

  defp parse_selector(selector) when is_binary(selector) do
    trimmed = String.trim(selector)

    cond do
      String.starts_with?(trimmed, "node") and trimmed not in ["node", "node[*]"] ->
        rest = String.slice(trimmed, 4..-1//1)

        parse_selector_tokens(rest, %{
          all_nodes?: false,
          id: nil,
          type: nil,
          shape: nil,
          classes: []
        })

      bare_shape_selector?(trimmed) ->
        {:ok, %{all_nodes?: false, id: nil, type: nil, shape: trimmed, classes: []}, 1}

      bare_type_selector?(trimmed) ->
        {:ok, %{all_nodes?: false, id: nil, type: trimmed, shape: nil, classes: []}, 1}

      true ->
        parse_selector_tokens(trimmed, %{
          all_nodes?: false,
          id: nil,
          type: nil,
          shape: nil,
          classes: []
        })
    end
  end

  defp parse_selector_tokens("", parsed), do: {:ok, parsed, selector_specificity(parsed)}

  defp parse_selector_tokens(rest, parsed) do
    cond do
      String.starts_with?(rest, "[shape=") ->
        parse_bracket_shape_selector(rest, parsed)

      String.starts_with?(rest, "shape=") ->
        parse_bare_shape_selector(rest, parsed)

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

  defp parse_bracket_shape_selector(rest, parsed) do
    case Regex.run(~r/^\[shape=([^\]]+)\](.*)$/, rest, capture: :all_but_first) do
      [raw_shape, remaining] ->
        with {:ok, shape} <- normalize_shape_token(raw_shape),
             :ok <- ensure_single_shape(parsed.shape) do
          parse_selector_tokens(remaining, %{parsed | shape: shape})
        else
          _ -> :error
        end

      _ ->
        :error
    end
  end

  defp parse_bare_shape_selector(rest, parsed) do
    case Regex.run(
           ~r/^shape=([A-Za-z_][A-Za-z0-9_\.\-]*|\"(?:[^\"\\]|\\.)+\"|'(?:[^'\\]|\\.)+')(.*)$/,
           rest,
           capture: :all_but_first
         ) do
      [raw_shape, remaining] ->
        with {:ok, shape} <- normalize_shape_token(raw_shape),
             :ok <- ensure_single_shape(parsed.shape) do
          parse_selector_tokens(remaining, %{parsed | shape: shape})
        else
          _ -> :error
        end

      _ ->
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
    case Regex.run(
           ~r/^type=([A-Za-z_][A-Za-z0-9_\.\-]*|\"(?:[^\"\\]|\\.)+\"|'(?:[^'\\]|\\.)+')(.*)$/,
           rest,
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

  defp normalize_shape_token(raw_shape), do: normalize_selector_ident(raw_shape)
  defp normalize_type_token(raw_type), do: normalize_selector_ident(raw_type)

  defp normalize_selector_ident(raw_value) do
    value =
      raw_value
      |> String.trim()
      |> trim_wrapping_quotes()

    if Regex.match?(@selector_ident, value) do
      {:ok, value}
    else
      :error
    end
  end

  defp ensure_single_shape(nil), do: :ok
  defp ensure_single_shape(_), do: :error

  defp ensure_single_type(nil), do: :ok
  defp ensure_single_type(_), do: :error

  defp selector_specificity(parsed) do
    id_score = if is_nil(parsed.id), do: 0, else: 100
    class_score = length(parsed.classes) * 10
    type_score = if is_nil(parsed.type) and is_nil(parsed.shape), do: 0, else: 1
    id_score + class_score + type_score
  end

  defp bare_shape_selector?(selector) do
    selector in [
      "Mdiamond",
      "Msquare",
      "box",
      "hexagon",
      "diamond",
      "component",
      "tripleoctagon",
      "parallelogram",
      "house"
    ]
  end

  defp bare_type_selector?(selector) do
    Regex.match?(@selector_ident, selector)
  end

  defp split_selector_list(text) do
    {parts, current, _in_quotes, _bracket_depth} =
      text
      |> String.graphemes()
      |> Enum.reduce({[], "", false, 0}, fn char, {parts, current, in_quotes, bracket_depth} ->
        cond do
          char in ["\"", "'"] and not escaped_quote?(current) ->
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

  defp lint_css_stylesheet(stylesheet) do
    case do_lint_css_stylesheet(stylesheet, [], 0) do
      {:ok, diagnostics} ->
        Enum.reverse(diagnostics)

      {:error, diagnostics} ->
        Enum.reverse(diagnostics)
    end
  end

  defp do_lint_css_stylesheet(remaining, diagnostics, index) do
    trimmed = String.trim(remaining)

    if trimmed == "" do
      {:ok, diagnostics}
    else
      case take_css_rule(trimmed) do
        {:ok, selector_text, declarations_text, next} ->
          selector_diagnostics = lint_css_selector(selector_text)
          declaration_diagnostics = lint_css_declarations(declarations_text, index)

          do_lint_css_stylesheet(
            next,
            Enum.reverse(selector_diagnostics) ++ declaration_diagnostics ++ diagnostics,
            index + 1
          )

        :error ->
          {:error,
           [
             lint_diag(
               :model_stylesheet_css_syntax,
               "model_stylesheet CSS rule has invalid syntax."
             )
             | diagnostics
           ]}
      end
    end
  end

  defp lint_css_declarations(text, rule_index) do
    text
    |> split_css_declarations()
    |> Enum.map(&String.trim/1)
    |> Enum.reduce([], fn declaration, acc ->
      case split_css_declaration(declaration) do
        [property, value] ->
          property = String.trim(property)
          value = String.trim(value)

          cond do
            property == "" or value == "" ->
              [
                lint_diag(
                  :model_stylesheet_css_declaration_invalid,
                  "model_stylesheet CSS declaration is invalid in rule #{rule_index}."
                )
                | acc
              ]

            not recognized_css_property?(property) ->
              [
                lint_diag(
                  :model_stylesheet_css_property_unknown,
                  "model_stylesheet CSS property `#{property}` is not supported."
                )
                | acc
              ]

            true ->
              acc
          end

        _ ->
          [
            lint_diag(
              :model_stylesheet_css_declaration_invalid,
              "model_stylesheet CSS declaration is invalid in rule #{rule_index}."
            )
            | acc
          ]
      end
    end)
  end

  defp maybe_put_css_declaration(acc, property, value) do
    normalized_property = normalize_css_property(property)

    normalized_value =
      value
      |> String.trim()
      |> trim_wrapping_quotes()

    if recognized_css_property?(normalized_property) and normalized_value != "" do
      Map.put(acc, normalized_property, normalized_value)
    else
      acc
    end
  end

  defp split_css_declaration(declaration) do
    case String.split(declaration, ":", parts: 2) do
      [property, value] -> [property, value]
      _ -> String.split(declaration, "=", parts: 2)
    end
  end

  defp normalize_css_property(property) do
    case String.trim(property) do
      "model" -> "llm_model"
      other -> other
    end
  end

  defp lint_diag(code, message) do
    %{severity: :warning, code: code, message: message, node_id: nil}
  end

  defp maybe_add_invalid_rule_attrs_diag(acc, _selector, attrs) when is_map(attrs), do: acc

  defp maybe_add_invalid_rule_attrs_diag(acc, selector, _attrs) do
    [
      lint_diag(
        :model_stylesheet_rule_attrs_invalid,
        "model_stylesheet rule for selector `#{selector}` should define attrs as a map."
      )
      | acc
    ]
  end

  defp maybe_add_invalid_selector_diag(acc, selector) do
    if valid_selector_list?(selector) do
      acc
    else
      [
        lint_diag(
          :model_stylesheet_selector_invalid,
          "model_stylesheet selector `#{selector}` is invalid and will be ignored."
        )
        | acc
      ]
    end
  end

  defp lint_css_selector(selector_text) do
    selector = String.trim(selector_text)

    if valid_selector_list?(selector) do
      []
    else
      [
        lint_diag(
          :model_stylesheet_selector_invalid,
          "model_stylesheet selector `#{selector}` is invalid and will be ignored."
        )
      ]
    end
  end

  defp valid_selector_list?(selector_text) when is_binary(selector_text) do
    selector_text
    |> split_selector_list()
    |> case do
      [] -> false
      selectors -> Enum.all?(selectors, &match?({:ok, _parsed, _rank}, parse_selector(&1)))
    end
  end

  defp valid_selector_list?(_selector_text), do: false

  defp strip_css_comments(stylesheet) do
    stylesheet
    |> do_strip_css_comments([], nil, false, :normal)
    |> IO.iodata_to_binary()
  end

  defp do_strip_css_comments(<<>>, acc, _quote, _escaped, :normal), do: Enum.reverse(acc)
  defp do_strip_css_comments(<<>>, acc, _quote, _escaped, :block_comment), do: Enum.reverse(acc)

  defp do_strip_css_comments(<<char, rest::binary>>, acc, quote, escaped, :normal) do
    cond do
      quote == nil and char == ?/ and match?(<<?*, _::binary>>, rest) ->
        <<_star, next::binary>> = rest
        do_strip_css_comments(next, acc, nil, false, :block_comment)

      char in [?", ?'] and quote == nil ->
        do_strip_css_comments(rest, [<<char>> | acc], char, false, :normal)

      char == quote and not escaped ->
        do_strip_css_comments(rest, [<<char>> | acc], nil, false, :normal)

      true ->
        next_escaped = quote != nil and char == ?\\ and not escaped
        do_strip_css_comments(rest, [<<char>> | acc], quote, next_escaped, :normal)
    end
  end

  defp do_strip_css_comments(<<"*/", rest::binary>>, acc, quote, _escaped, :block_comment) do
    do_strip_css_comments(rest, acc, quote, false, :normal)
  end

  defp do_strip_css_comments(<<_char, rest::binary>>, acc, quote, _escaped, :block_comment) do
    do_strip_css_comments(rest, acc, quote, false, :block_comment)
  end

  defp split_css_declarations(text) do
    {parts, current, _quote} =
      text
      |> String.graphemes()
      |> Enum.reduce({[], "", nil}, fn char, {parts, current, quote} ->
        cond do
          char in ["\"", "'"] and is_nil(quote) and not escaped_quote?(current) ->
            {parts, current <> char, char}

          char == quote and not escaped_quote?(current) ->
            {parts, current <> char, nil}

          char == ";" and is_nil(quote) ->
            {[current | parts], "", quote}

          true ->
            {parts, current <> char, quote}
        end
      end)

    [current | parts]
    |> Enum.reverse()
    |> Enum.reject(&(String.trim(&1) == ""))
  end

  defp take_css_rule(stylesheet) do
    case String.split(stylesheet, "{", parts: 2) do
      [selector, rest] ->
        case take_until_closing_brace(rest, "", nil) do
          {declarations, next} when is_binary(next) ->
            {:ok, String.trim(selector), declarations, next}

          {_declarations, nil} ->
            :error
        end

      _ ->
        :error
    end
  end

  defp take_until_closing_brace(text, current, quote) do
    case String.next_grapheme(text) do
      nil ->
        {current, nil}

      {char, rest} when char in ["\"", "'"] and is_nil(quote) ->
        take_until_closing_brace(rest, current <> char, char)

      {char, rest} ->
        cond do
          char == quote and not escaped_quote?(current) ->
            take_until_closing_brace(rest, current <> char, nil)

          char == "}" and is_nil(quote) ->
            {current, rest}

          true ->
            take_until_closing_brace(rest, current <> char, quote)
        end
    end
  end

  defp escaped_quote?(current) do
    trailing_backslashes =
      current
      |> String.reverse()
      |> String.graphemes()
      |> Enum.take_while(&(&1 == "\\"))
      |> length()

    rem(trailing_backslashes, 2) == 1
  end
end
