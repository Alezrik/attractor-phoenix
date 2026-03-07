defmodule AttractorEx.Validator do
  @moduledoc false

  alias AttractorEx.{Condition, Graph, HandlerRegistry, HumanGate, ModelStylesheet}

  @valid_fidelity_values [
    "full",
    "truncate",
    "compact",
    "summary:low",
    "summary:medium",
    "summary:high"
  ]

  def validate(%Graph{} = graph, opts \\ []) do
    []
    |> validate_start_node(graph)
    |> validate_terminal_nodes(graph)
    |> validate_start_incoming(graph)
    |> validate_exit_outgoing(graph)
    |> validate_edge_targets(graph)
    |> validate_unreachable_nodes(graph)
    |> validate_dead_end_nodes(graph)
    |> validate_condition_expressions(graph)
    |> validate_goal_gate_retry(graph)
    |> validate_retry_target_nodes(graph)
    |> validate_codergen_prompt(graph)
    |> validate_known_node_types(graph)
    |> validate_fidelity_values(graph)
    |> validate_human_gate_choices(graph)
    |> validate_human_default_choice(graph)
    |> validate_human_timeout_default(graph)
    |> validate_human_choice_key_collisions(graph)
    |> validate_codergen_llm_attrs(graph)
    |> validate_model_stylesheet_syntax(graph)
    |> validate_model_stylesheet_lints(graph)
    |> apply_custom_rules(graph, opts)
  end

  def start_node_id(%Graph{} = graph) do
    graph.nodes
    |> Enum.find_value(fn {id, node} ->
      if node.type == "start" or String.downcase(id) == "start", do: id, else: nil
    end)
  end

  defp validate_start_node(diags, graph) do
    start_count =
      graph.nodes
      |> Enum.count(fn {id, node} -> node.type == "start" or String.downcase(id) == "start" end)

    if start_count == 1 do
      diags
    else
      [diag(:error, :start_node, "Pipeline must have exactly one start node.") | diags]
    end
  end

  defp validate_terminal_nodes(diags, graph) do
    terminal_count =
      graph.nodes
      |> Enum.count(fn {id, node} ->
        node.type == "exit" or String.downcase(id) in ["exit", "end"]
      end)

    if terminal_count == 1 do
      diags
    else
      [diag(:error, :terminal_node, "Pipeline must have exactly one terminal node.") | diags]
    end
  end

  defp validate_start_incoming(diags, graph) do
    start_id = start_node_id(graph)

    if is_nil(start_id) do
      diags
    else
      incoming = Enum.any?(graph.edges, &(&1.to == start_id))

      if incoming do
        [
          diag(:error, :start_no_incoming, "Start node must not have incoming edges.", start_id)
          | diags
        ]
      else
        diags
      end
    end
  end

  defp validate_exit_outgoing(diags, graph) do
    exit_ids =
      graph.nodes
      |> Enum.filter(fn {id, node} ->
        node.type == "exit" or String.downcase(id) in ["exit", "end"]
      end)
      |> Enum.map(&elem(&1, 0))

    Enum.reduce(exit_ids, diags, fn exit_id, acc ->
      outgoing = Enum.any?(graph.edges, &(&1.from == exit_id))

      if outgoing do
        [diag(:error, :exit_no_outgoing, "Exit node must have no outgoing edges.", exit_id) | acc]
      else
        acc
      end
    end)
  end

  defp validate_condition_expressions(diags, graph) do
    Enum.reduce(graph.edges, diags, fn edge, acc ->
      if is_binary(edge.condition) and not Condition.valid?(edge.condition) do
        [
          diag(
            :error,
            :condition_parse,
            "Edge condition is invalid: #{edge.condition}",
            edge.from,
            {edge.from, edge.to}
          )
          | acc
        ]
      else
        acc
      end
    end)
  end

  defp validate_edge_targets(diags, graph) do
    node_ids = MapSet.new(Map.keys(graph.nodes))

    Enum.reduce(graph.edges, diags, fn edge, acc ->
      if MapSet.member?(node_ids, edge.to) do
        acc
      else
        [
          diag(
            :error,
            :edge_target_exists,
            "Edge target references an unknown node.",
            edge.from,
            {edge.from, edge.to}
          )
          | acc
        ]
      end
    end)
  end

  defp validate_unreachable_nodes(diags, graph) do
    start_id = start_node_id(graph)

    if is_nil(start_id) do
      diags
    else
      reachable = reachable_nodes(start_id, graph)

      Enum.reduce(graph.nodes, diags, fn {id, _node}, acc ->
        if id in reachable do
          acc
        else
          [
            diag(
              :error,
              :reachability,
              "Node is not reachable from start.",
              id
            )
            | acc
          ]
        end
      end)
    end
  end

  defp validate_dead_end_nodes(diags, graph) do
    Enum.reduce(graph.nodes, diags, fn {_id, node}, acc ->
      terminal? = node.type == "exit" or String.downcase(node.id) in ["exit", "end"]
      has_outgoing? = Enum.any?(graph.edges, &(&1.from == node.id))
      has_retry_path? = not is_nil(node.retry_target) or not is_nil(node.fallback_retry_target)

      if terminal? or has_outgoing? or has_retry_path? do
        acc
      else
        [diag(:warning, :dead_end_node, "Non-exit node has no outgoing path.", node.id) | acc]
      end
    end)
  end

  defp validate_goal_gate_retry(diags, graph) do
    Enum.reduce(graph.nodes, diags, fn {_id, node}, acc ->
      if node.goal_gate and is_nil(node.retry_target) and is_nil(node.fallback_retry_target) do
        [
          diag(
            :warning,
            :goal_gate_has_retry,
            "Goal-gate node should define retry_target or fallback_retry_target.",
            node.id
          )
          | acc
        ]
      else
        acc
      end
    end)
  end

  defp validate_retry_target_nodes(diags, graph) do
    node_ids = MapSet.new(Map.keys(graph.nodes))

    Enum.reduce(graph.nodes, diags, fn {_id, node}, acc ->
      acc
      |> maybe_add_missing_retry_target(node, node_ids)
      |> maybe_add_missing_fallback_retry_target(node, node_ids)
    end)
  end

  defp maybe_add_missing_retry_target(diags, node, node_ids) do
    maybe_add_missing_target_diag(
      diags,
      node,
      node.retry_target,
      node_ids,
      :retry_target_missing,
      "retry_target points to an unknown node."
    )
  end

  defp maybe_add_missing_fallback_retry_target(diags, node, node_ids) do
    maybe_add_missing_target_diag(
      diags,
      node,
      node.fallback_retry_target,
      node_ids,
      :fallback_retry_target_missing,
      "fallback_retry_target points to an unknown node."
    )
  end

  defp maybe_add_missing_target_diag(diags, _node, nil, _node_ids, _code, _message), do: diags

  defp maybe_add_missing_target_diag(diags, node, target, node_ids, code, message) do
    if MapSet.member?(node_ids, target) do
      diags
    else
      [diag(:error, code, message, node.id) | diags]
    end
  end

  defp validate_codergen_prompt(diags, graph) do
    Enum.reduce(graph.nodes, diags, fn {_id, node}, acc ->
      if node.type == "codergen" and String.trim(node.prompt) == "" do
        [diag(:warning, :codergen_prompt, "Codergen node has no prompt.", node.id) | acc]
      else
        acc
      end
    end)
  end

  defp validate_known_node_types(diags, graph) do
    Enum.reduce(graph.nodes, diags, fn {_id, node}, acc ->
      explicit_type = blank_to_nil(Map.get(node.attrs, "type"))

      if explicit_type && not HandlerRegistry.known_type?(explicit_type) do
        [
          diag(
            :warning,
            :type_known,
            "Node type `#{explicit_type}` is not recognized by the handler registry.",
            node.id
          )
          | acc
        ]
      else
        acc
      end
    end)
  end

  defp validate_fidelity_values(diags, graph) do
    diags
    |> maybe_add_invalid_fidelity_diag(
      Map.get(graph.attrs, "default_fidelity"),
      :fidelity_valid,
      "Graph default_fidelity must be one of: #{Enum.join(@valid_fidelity_values, ", ")}."
    )
    |> validate_node_fidelity_values(graph)
    |> validate_edge_fidelity_values(graph)
  end

  defp validate_node_fidelity_values(diags, graph) do
    Enum.reduce(graph.nodes, diags, fn {_id, node}, acc ->
      maybe_add_invalid_fidelity_diag(
        acc,
        Map.get(node.attrs, "fidelity"),
        :fidelity_valid,
        "Node fidelity must be one of: #{Enum.join(@valid_fidelity_values, ", ")}.",
        node.id
      )
    end)
  end

  defp validate_edge_fidelity_values(diags, graph) do
    Enum.reduce(graph.edges, diags, fn edge, acc ->
      maybe_add_invalid_fidelity_diag(
        acc,
        Map.get(edge.attrs, "fidelity"),
        :fidelity_valid,
        "Edge fidelity must be one of: #{Enum.join(@valid_fidelity_values, ", ")}.",
        edge.from,
        {edge.from, edge.to}
      )
    end)
  end

  defp maybe_add_invalid_fidelity_diag(diags, value, _code, _message, node_id \\ nil, edge \\ nil)

  defp maybe_add_invalid_fidelity_diag(diags, value, _code, _message, _node_id, _edge)
       when value in [nil, ""] do
    diags
  end

  defp maybe_add_invalid_fidelity_diag(diags, value, code, message, node_id, edge) do
    normalized = value |> to_string() |> String.trim()

    if normalized in @valid_fidelity_values do
      diags
    else
      [diag(:warning, code, message, node_id, edge) | diags]
    end
  end

  defp validate_human_gate_choices(diags, graph) do
    Enum.reduce(graph.nodes, diags, fn {_id, node}, acc ->
      if node.type == "wait.human" do
        choices = HumanGate.choices_for(node.id, graph)

        cond do
          choices == [] ->
            [
              diag(
                :error,
                :human_gate_choices,
                "wait.human node must have at least one outgoing edge.",
                node.id
              )
              | acc
            ]

          Enum.any?(choices, &(not is_binary(&1.label) or String.trim(&1.label) == "")) ->
            [
              diag(
                :warning,
                :human_gate_choice_label,
                "wait.human choices should define non-empty labels.",
                node.id
              )
              | acc
            ]

          true ->
            acc
        end
      else
        acc
      end
    end)
  end

  defp validate_human_default_choice(diags, graph) do
    Enum.reduce(graph.nodes, diags, fn {_id, node}, acc ->
      default_choice = Map.get(node.attrs, "human.default_choice")

      if node.type == "wait.human" and is_binary(default_choice) and
           String.trim(default_choice) != "" do
        choices = HumanGate.choices_for(node.id, graph)

        if is_nil(HumanGate.match_choice(default_choice, choices)) do
          [
            diag(
              :warning,
              :human_default_choice,
              "human.default_choice does not match any outgoing choice.",
              node.id
            )
            | acc
          ]
        else
          acc
        end
      else
        acc
      end
    end)
  end

  defp validate_human_timeout_default(diags, graph) do
    Enum.reduce(graph.nodes, diags, fn {_id, node}, acc ->
      timeout_value = Map.get(node.attrs, "human.timeout")
      default_choice = Map.get(node.attrs, "human.default_choice")

      if node.type == "wait.human" and not is_nil(timeout_value) and
           blank?(default_choice) do
        [
          diag(
            :warning,
            :human_timeout_without_default,
            "wait.human node sets human.timeout but has no human.default_choice.",
            node.id
          )
          | acc
        ]
      else
        acc
      end
    end)
  end

  defp validate_human_choice_key_collisions(diags, graph) do
    Enum.reduce(graph.nodes, diags, fn {_id, node}, acc ->
      if node.type == "wait.human" do
        choices = HumanGate.choices_for(node.id, graph)

        has_duplicate_keys? =
          choices
          |> Enum.map(&HumanGate.normalize_token(&1.key))
          |> Enum.reject(&(&1 == ""))
          |> duplicate_values?()

        if has_duplicate_keys? do
          [
            diag(
              :warning,
              :human_gate_duplicate_keys,
              "wait.human choices produce duplicate accelerator keys.",
              node.id
            )
            | acc
          ]
        else
          acc
        end
      else
        acc
      end
    end)
  end

  defp validate_codergen_llm_attrs(diags, graph) do
    Enum.reduce(graph.nodes, diags, fn {_id, node}, acc ->
      if node.type == "codergen" do
        acc
        |> validate_reasoning_effort(node)
        |> validate_temperature(node)
        |> validate_max_tokens(node)
        |> validate_provider_model_pair(node)
      else
        acc
      end
    end)
  end

  defp validate_reasoning_effort(diags, node) do
    case Map.get(node.attrs, "reasoning_effort") do
      nil ->
        diags

      value when is_binary(value) ->
        normalized = value |> String.trim() |> String.downcase()

        if normalized in ["low", "medium", "high"] do
          diags
        else
          [
            diag(
              :warning,
              :reasoning_effort_invalid,
              "reasoning_effort should be one of: low, medium, high.",
              node.id
            )
            | diags
          ]
        end

      _value ->
        [
          diag(
            :warning,
            :reasoning_effort_invalid,
            "reasoning_effort should be one of: low, medium, high.",
            node.id
          )
          | diags
        ]
    end
  end

  defp validate_temperature(diags, node) do
    case Map.get(node.attrs, "temperature") do
      nil ->
        diags

      value ->
        case to_float(value) do
          {:ok, number} when number >= 0.0 and number <= 2.0 ->
            diags

          _ ->
            [
              diag(
                :warning,
                :temperature_invalid,
                "temperature should be a number between 0 and 2.",
                node.id
              )
              | diags
            ]
        end
    end
  end

  defp validate_max_tokens(diags, node) do
    case Map.get(node.attrs, "max_tokens") do
      nil ->
        diags

      value ->
        case to_positive_integer(value) do
          {:ok, _parsed} ->
            diags

          :error ->
            [
              diag(
                :warning,
                :max_tokens_invalid,
                "max_tokens should be a positive integer.",
                node.id
              )
              | diags
            ]
        end
    end
  end

  defp validate_provider_model_pair(diags, node) do
    provider = blank_to_nil(Map.get(node.attrs, "llm_provider"))
    model = blank_to_nil(Map.get(node.attrs, "llm_model"))

    if provider && is_nil(model) do
      [
        diag(
          :warning,
          :llm_provider_without_model,
          "llm_provider is set but llm_model is missing for codergen node.",
          node.id
        )
        | diags
      ]
    else
      diags
    end
  end

  defp validate_model_stylesheet_lints(diags, graph) do
    style_diags =
      graph.attrs
      |> Map.get("model_stylesheet")
      |> ModelStylesheet.lint()

    Enum.reverse(style_diags) ++ diags
  end

  defp validate_model_stylesheet_syntax(diags, graph) do
    case ModelStylesheet.parse(Map.get(graph.attrs, "model_stylesheet")) do
      {:ok, _rules} ->
        diags

      {:error, _reason} ->
        [
          diag(
            :error,
            :stylesheet_syntax,
            "The model_stylesheet attribute must parse as valid stylesheet rules."
          )
          | diags
        ]
    end
  end

  defp apply_custom_rules(diags, graph, opts) do
    rules = Keyword.get(opts, :custom_rules, [])

    Enum.reduce(rules, diags, fn rule, acc ->
      case apply_custom_rule(rule, graph) do
        [] ->
          acc

        rule_diags when is_list(rule_diags) ->
          Enum.reduce(rule_diags, acc, fn item, next ->
            case normalize_custom_diag(item) do
              nil -> next
              diag -> [diag | next]
            end
          end)

        item ->
          case normalize_custom_diag(item) do
            nil ->
              [diag(:warning, :custom_rule_invalid, "Custom rule returned invalid value.") | acc]

            diag ->
              [diag | acc]
          end
      end
    end)
  end

  defp apply_custom_rule(rule, graph) when is_function(rule, 1), do: safe_custom_rule(rule, graph)

  defp apply_custom_rule(rule, graph) when is_atom(rule) do
    if Code.ensure_loaded?(rule) and function_exported?(rule, :validate, 1) do
      safe_custom_rule(rule, graph)
    else
      nil
    end
  end

  defp apply_custom_rule(_rule, _graph), do: nil

  defp safe_custom_rule(rule_fun, graph) when is_function(rule_fun, 1) do
    rule_fun.(graph)
  rescue
    _error -> nil
  end

  defp safe_custom_rule(rule, graph) do
    rule.validate(graph)
  rescue
    _error -> nil
  end

  defp normalize_custom_diag(%{severity: severity, code: code, message: message} = diag_map)
       when severity in [:error, :warning] and is_atom(code) and is_binary(message) do
    %{
      severity: severity,
      code: code,
      message: message,
      node_id: Map.get(diag_map, :node_id),
      edge: Map.get(diag_map, :edge)
    }
  end

  defp normalize_custom_diag(_), do: nil

  defp diag(severity, code, message, node_id \\ nil, edge \\ nil) do
    %{severity: severity, code: code, message: message, node_id: node_id, edge: edge}
  end

  defp to_float(value) when is_float(value), do: {:ok, value}
  defp to_float(value) when is_integer(value), do: {:ok, value * 1.0}

  defp to_float(value) when is_binary(value) do
    case Float.parse(String.trim(value)) do
      {parsed, ""} -> {:ok, parsed}
      _ -> :error
    end
  end

  defp to_float(_), do: :error

  defp to_positive_integer(value) when is_integer(value),
    do: if(value > 0, do: {:ok, value}, else: :error)

  defp to_positive_integer(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {parsed, ""} when parsed > 0 -> {:ok, parsed}
      _ -> :error
    end
  end

  defp to_positive_integer(_), do: :error

  defp blank_to_nil(nil), do: nil

  defp blank_to_nil(value) do
    trimmed = value |> to_string() |> String.trim()
    if trimmed == "", do: nil, else: trimmed
  end

  defp blank?(value), do: is_nil(blank_to_nil(value))

  defp duplicate_values?(values) do
    values
    |> Enum.frequencies()
    |> Enum.any?(fn {_value, count} -> count > 1 end)
  end

  defp reachable_nodes(start_id, %Graph{} = graph) do
    edge_adjacency =
      graph.edges
      |> Enum.group_by(& &1.from, & &1.to)
      |> Map.new(fn {from, to_nodes} -> {from, MapSet.new(to_nodes)} end)

    retry_adjacency =
      graph.nodes
      |> Enum.reduce(%{}, fn {_id, node}, acc ->
        targets =
          [node.retry_target, node.fallback_retry_target]
          |> Enum.reject(&is_nil/1)
          |> MapSet.new()

        if MapSet.size(targets) == 0 do
          acc
        else
          Map.update(acc, node.id, targets, &MapSet.union(&1, targets))
        end
      end)

    adjacency =
      Map.merge(edge_adjacency, retry_adjacency, fn _key, left, right ->
        MapSet.union(left, right)
      end)

    do_reachable_nodes(MapSet.new([start_id]), [start_id], adjacency)
  end

  defp do_reachable_nodes(visited, [], _adjacency), do: MapSet.to_list(visited)

  defp do_reachable_nodes(visited, [current | queue], adjacency) do
    next_nodes = Map.get(adjacency, current, MapSet.new())

    {visited, queue} =
      Enum.reduce(next_nodes, {visited, queue}, fn next, {v, q} ->
        if MapSet.member?(v, next) do
          {v, q}
        else
          {MapSet.put(v, next), q ++ [next]}
        end
      end)

    do_reachable_nodes(visited, queue, adjacency)
  end
end
