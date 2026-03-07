defmodule AttractorEx.Validator do
  @moduledoc false

  alias AttractorEx.{Condition, Graph, HumanGate}

  def validate(%Graph{} = graph, opts \\ []) do
    []
    |> validate_start_node(graph)
    |> validate_terminal_nodes(graph)
    |> validate_start_incoming(graph)
    |> validate_exit_outgoing(graph)
    |> validate_condition_expressions(graph)
    |> validate_goal_gate_retry(graph)
    |> validate_codergen_prompt(graph)
    |> validate_human_gate_choices(graph)
    |> validate_human_default_choice(graph)
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
            edge.from
          )
          | acc
        ]
      else
        acc
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

  defp validate_codergen_prompt(diags, graph) do
    Enum.reduce(graph.nodes, diags, fn {_id, node}, acc ->
      if node.type == "codergen" and String.trim(node.prompt) == "" do
        [diag(:warning, :codergen_prompt, "Codergen node has no prompt.", node.id) | acc]
      else
        acc
      end
    end)
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
    if function_exported?(rule, :validate, 1) do
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
      node_id: Map.get(diag_map, :node_id)
    }
  end

  defp normalize_custom_diag(_), do: nil

  defp diag(severity, code, message, node_id \\ nil) do
    %{severity: severity, code: code, message: message, node_id: node_id}
  end
end
