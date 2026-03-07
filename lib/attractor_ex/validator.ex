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
    |> validate_edge_sources(graph)
    |> validate_edge_targets(graph)
    |> validate_unreachable_nodes(graph)
    |> validate_dead_end_nodes(graph)
    |> validate_condition_expressions(graph)
    |> validate_goal_gate_retry(graph)
    |> validate_graph_retry_target_nodes(graph)
    |> validate_retry_target_nodes(graph)
    |> validate_retry_counts(graph)
    |> validate_llm_node_prompt(graph)
    |> validate_known_node_types(graph)
    |> validate_fidelity_values(graph)
    |> validate_human_gate_choices(graph)
    |> validate_human_prompt(graph)
    |> validate_human_default_choice(graph)
    |> validate_human_default_choice_ambiguity(graph)
    |> validate_human_multiple_setting(graph)
    |> validate_human_multiple_choice_count(graph)
    |> validate_human_timeout_default(graph)
    |> validate_human_timeout_format(graph)
    |> validate_human_choice_key_collisions(graph)
    |> validate_codergen_llm_attrs(graph)
    |> validate_parallel_attrs(graph)
    |> validate_stack_manager_attrs(graph)
    |> validate_model_stylesheet_syntax(graph)
    |> validate_model_stylesheet_lints(graph)
    |> apply_custom_rules(graph, opts)
  end

  def validate_or_raise(%Graph{} = graph, opts \\ []) do
    diagnostics = validate(graph, opts)
    errors = Enum.filter(diagnostics, &(&1.severity == :error))

    if errors == [] do
      diagnostics
    else
      formatted =
        errors
        |> Enum.map_join("\n", fn diag ->
          location =
            cond do
              is_binary(diag.node_id) -> " node=#{diag.node_id}"
              is_tuple(diag.edge) -> " edge=#{elem(diag.edge, 0)}->#{elem(diag.edge, 1)}"
              true -> ""
            end

          "[#{diag.code}]#{location} #{diag.message}"
        end)

      raise ArgumentError, "Attractor validation failed:\n" <> formatted
    end
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

  defp validate_edge_sources(diags, graph) do
    node_ids = MapSet.new(Map.keys(graph.nodes))

    Enum.reduce(graph.edges, diags, fn edge, acc ->
      if MapSet.member?(node_ids, edge.from) do
        acc
      else
        [
          diag(
            :error,
            :edge_source_exists,
            "Edge source references an unknown node.",
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

  defp validate_graph_retry_target_nodes(diags, graph) do
    node_ids = MapSet.new(Map.keys(graph.nodes))

    diags
    |> maybe_add_missing_graph_target_diag(
      Map.get(graph.attrs, "retry_target"),
      node_ids,
      :graph_retry_target_missing,
      "Graph retry_target points to an unknown node."
    )
    |> maybe_add_missing_graph_target_diag(
      Map.get(graph.attrs, "fallback_retry_target"),
      node_ids,
      :graph_fallback_retry_target_missing,
      "Graph fallback_retry_target points to an unknown node."
    )
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

  defp maybe_add_missing_graph_target_diag(diags, nil, _node_ids, _code, _message), do: diags

  defp maybe_add_missing_graph_target_diag(diags, target, node_ids, code, message) do
    if MapSet.member?(node_ids, target) do
      diags
    else
      [diag(:error, code, message) | diags]
    end
  end

  defp validate_llm_node_prompt(diags, graph) do
    Enum.reduce(graph.nodes, diags, fn {_id, node}, acc ->
      prompt = blank_to_nil(node.prompt)
      label = blank_to_nil(Map.get(node.attrs, "label"))

      if node.type == "codergen" and is_nil(prompt) and is_nil(label) do
        [
          diag(
            :warning,
            :prompt_on_llm_nodes,
            "LLM-backed box nodes should define a prompt or label.",
            node.id
          )
          | acc
        ]
      else
        acc
      end
    end)
  end

  defp validate_retry_counts(diags, graph) do
    diags
    |> validate_graph_default_max_retry(graph)
    |> validate_node_max_retries(graph)
  end

  defp validate_graph_default_max_retry(diags, graph) do
    case Map.get(graph.attrs, "default_max_retry") do
      nil ->
        diags

      value ->
        if valid_non_negative_integer?(value) do
          diags
        else
          [
            diag(
              :warning,
              :default_max_retry_invalid,
              "Graph default_max_retry should be a non-negative integer."
            )
            | diags
          ]
        end
    end
  end

  defp validate_node_max_retries(diags, graph) do
    Enum.reduce(graph.nodes, diags, fn {_id, node}, acc ->
      case Map.get(node.attrs, "max_retries") do
        nil ->
          acc

        value ->
          if valid_non_negative_integer?(value) do
            acc
          else
            [
              diag(
                :warning,
                :max_retries_invalid,
                "Node max_retries should be a non-negative integer.",
                node.id
              )
              | acc
            ]
          end
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

  defp validate_human_prompt(diags, graph) do
    Enum.reduce(graph.nodes, diags, fn {_id, node}, acc ->
      if node.type == "wait.human" and blank?(Map.get(node.attrs, "prompt")) do
        [
          diag(
            :warning,
            :human_gate_prompt,
            "wait.human node should define a prompt for interviewer UX.",
            node.id
          )
          | acc
        ]
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

  defp validate_human_default_choice_ambiguity(diags, graph) do
    Enum.reduce(graph.nodes, diags, fn {_id, node}, acc ->
      default_choice = Map.get(node.attrs, "human.default_choice")

      if node.type == "wait.human" and is_binary(default_choice) and
           String.trim(default_choice) != "" do
        choices = HumanGate.choices_for(node.id, graph)

        if ambiguous_human_default_choice?(default_choice, choices) do
          [
            diag(
              :warning,
              :human_default_choice_ambiguous,
              "human.default_choice matches multiple outgoing choices.",
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

  defp validate_human_multiple_setting(diags, graph) do
    Enum.reduce(graph.nodes, diags, fn {_id, node}, acc ->
      value = Map.get(node.attrs, "human.multiple")

      if node.type == "wait.human" and not is_nil(value) and not valid_boolean_setting?(value) do
        [
          diag(
            :warning,
            :human_multiple_invalid,
            "human.multiple should be true/false, yes/no, or 1/0.",
            node.id
          )
          | acc
        ]
      else
        acc
      end
    end)
  end

  defp validate_human_multiple_choice_count(diags, graph) do
    Enum.reduce(graph.nodes, diags, fn {_id, node}, acc ->
      if node.type == "wait.human" and truthy?(Map.get(node.attrs, "human.multiple")) do
        choices = HumanGate.choices_for(node.id, graph)

        if length(choices) < 2 do
          [
            diag(
              :warning,
              :human_multiple_requires_multiple_choices,
              "wait.human node sets human.multiple but has fewer than two outgoing choices.",
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

  defp validate_human_timeout_format(diags, graph) do
    Enum.reduce(graph.nodes, diags, fn {_id, node}, acc ->
      timeout_value = Map.get(node.attrs, "human.timeout")

      if node.type == "wait.human" and not is_nil(timeout_value) and
           not valid_human_timeout?(timeout_value) do
        [
          diag(
            :warning,
            :human_timeout_invalid,
            "human.timeout should be a positive integer or duration like 30s, 5m, or 500ms.",
            node.id
          )
          | acc
        ]
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

  defp validate_parallel_attrs(diags, graph) do
    Enum.reduce(graph.nodes, diags, fn {_id, node}, acc ->
      if node.type == "parallel" do
        acc
        |> validate_parallel_join_policy(node)
        |> validate_parallel_max_parallel(node)
        |> validate_parallel_k(node)
        |> validate_parallel_quorum_ratio(node)
      else
        acc
      end
    end)
  end

  defp validate_stack_manager_attrs(diags, graph) do
    Enum.reduce(graph.nodes, diags, fn {_id, node}, acc ->
      if node.type == "stack.manager_loop" do
        acc
        |> validate_manager_actions(node)
        |> validate_manager_max_cycles(node)
        |> validate_manager_poll_interval(node)
        |> validate_manager_child_dotfile(node, graph)
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

  defp validate_parallel_join_policy(diags, node) do
    case blank_to_nil(Map.get(node.attrs, "join_policy")) do
      nil ->
        diags

      value when value in ["wait_all", "first_success", "k_of_n", "quorum"] ->
        diags

      _value ->
        [
          diag(
            :warning,
            :parallel_join_policy_invalid,
            "parallel join_policy should be one of: wait_all, first_success, k_of_n, quorum.",
            node.id
          )
          | diags
        ]
    end
  end

  defp validate_parallel_max_parallel(diags, node) do
    case Map.get(node.attrs, "max_parallel") do
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
                :parallel_max_parallel_invalid,
                "parallel max_parallel should be a positive integer.",
                node.id
              )
              | diags
            ]
        end
    end
  end

  defp validate_parallel_k(diags, node) do
    join_policy = blank_to_nil(Map.get(node.attrs, "join_policy"))
    k_value = Map.get(node.attrs, "k")

    cond do
      join_policy == "k_of_n" and is_nil(k_value) ->
        [
          diag(
            :warning,
            :parallel_k_missing,
            "parallel join_policy=k_of_n should define k.",
            node.id
          )
          | diags
        ]

      join_policy == "k_of_n" ->
        case to_positive_integer(k_value) do
          {:ok, _parsed} ->
            diags

          :error ->
            [
              diag(
                :warning,
                :parallel_k_invalid,
                "parallel k should be a positive integer when join_policy=k_of_n.",
                node.id
              )
              | diags
            ]
        end

      not is_nil(k_value) ->
        [
          diag(
            :warning,
            :parallel_k_unused,
            "parallel k is set but join_policy is not k_of_n.",
            node.id
          )
          | diags
        ]

      true ->
        diags
    end
  end

  defp validate_parallel_quorum_ratio(diags, node) do
    join_policy = blank_to_nil(Map.get(node.attrs, "join_policy"))
    quorum_ratio = Map.get(node.attrs, "quorum_ratio")

    cond do
      join_policy == "quorum" and is_nil(quorum_ratio) ->
        [
          diag(
            :warning,
            :parallel_quorum_ratio_missing,
            "parallel join_policy=quorum should define quorum_ratio.",
            node.id
          )
          | diags
        ]

      join_policy == "quorum" ->
        case to_float(quorum_ratio) do
          {:ok, value} when value > 0.0 and value <= 1.0 ->
            diags

          _ ->
            [
              diag(
                :warning,
                :parallel_quorum_ratio_invalid,
                "parallel quorum_ratio should be a number greater than 0 and less than or equal to 1.",
                node.id
              )
              | diags
            ]
        end

      not is_nil(quorum_ratio) ->
        [
          diag(
            :warning,
            :parallel_quorum_ratio_unused,
            "parallel quorum_ratio is set but join_policy is not quorum.",
            node.id
          )
          | diags
        ]

      true ->
        diags
    end
  end

  defp validate_manager_actions(diags, node) do
    case blank_to_nil(Map.get(node.attrs, "manager.actions")) do
      nil ->
        diags

      value ->
        actions =
          value
          |> String.split(",", trim: true)
          |> Enum.map(&String.trim/1)
          |> Enum.reject(&(&1 == ""))

        cond do
          actions == [] ->
            [
              diag(
                :warning,
                :manager_actions_invalid,
                "manager.actions should include one or more of: observe, wait, steer.",
                node.id
              )
              | diags
            ]

          Enum.all?(actions, &(&1 in ["observe", "wait", "steer"])) ->
            diags

          true ->
            [
              diag(
                :warning,
                :manager_actions_invalid,
                "manager.actions should only include: observe, wait, steer.",
                node.id
              )
              | diags
            ]
        end
    end
  end

  defp validate_manager_max_cycles(diags, node) do
    case Map.get(node.attrs, "manager.max_cycles") do
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
                :manager_max_cycles_invalid,
                "manager.max_cycles should be a positive integer.",
                node.id
              )
              | diags
            ]
        end
    end
  end

  defp validate_manager_poll_interval(diags, node) do
    case Map.get(node.attrs, "manager.poll_interval") do
      nil ->
        diags

      value when is_integer(value) and value >= 0 ->
        diags

      value when is_binary(value) ->
        normalized = String.trim(value)

        if Regex.match?(~r/^\d+(ms|s|m|h|d)$/, normalized) do
          diags
        else
          [
            diag(
              :warning,
              :manager_poll_interval_invalid,
              "manager.poll_interval should be a non-negative duration like 500ms, 30s, 5m, 1h, or 1d.",
              node.id
            )
            | diags
          ]
        end

      _value ->
        [
          diag(
            :warning,
            :manager_poll_interval_invalid,
            "manager.poll_interval should be a non-negative duration like 500ms, 30s, 5m, 1h, or 1d.",
            node.id
          )
          | diags
        ]
    end
  end

  defp validate_manager_child_dotfile(diags, node, graph) do
    autostart_value = Map.get(node.attrs, "stack.child_autostart", "true")

    if truthy?(autostart_value) and blank?(Map.get(graph.attrs, "stack.child_dotfile")) do
      [
        diag(
          :warning,
          :manager_child_dotfile_missing,
          "stack.manager_loop autostart expects graph stack.child_dotfile to be set.",
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

  defp valid_non_negative_integer?(value) when is_integer(value), do: value >= 0

  defp valid_non_negative_integer?(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {parsed, ""} -> parsed >= 0
      _ -> false
    end
  end

  defp valid_non_negative_integer?(_value), do: false

  defp blank_to_nil(nil), do: nil

  defp blank_to_nil(value) do
    trimmed = value |> to_string() |> String.trim()
    if trimmed == "", do: nil, else: trimmed
  end

  defp blank?(value), do: is_nil(blank_to_nil(value))

  defp truthy?(value) when is_boolean(value), do: value

  defp truthy?(value) when is_binary(value) do
    String.downcase(String.trim(value)) in ["true", "1", "yes"]
  end

  defp truthy?(_value), do: false

  defp valid_boolean_setting?(value) when is_boolean(value), do: true

  defp valid_boolean_setting?(value) when is_binary(value) do
    String.downcase(String.trim(value)) in ["true", "false", "1", "0", "yes", "no"]
  end

  defp valid_boolean_setting?(_value), do: false

  defp duplicate_values?(values) do
    values
    |> Enum.frequencies()
    |> Enum.any?(fn {_value, count} -> count > 1 end)
  end

  defp ambiguous_human_default_choice?(value, choices) do
    normalized = HumanGate.normalize_token(value)

    choices
    |> Enum.count(fn choice ->
      HumanGate.normalize_token(choice.key) == normalized or
        HumanGate.normalize_token(choice.label) == normalized or
        HumanGate.normalize_token(choice.to) == normalized
    end)
    |> Kernel.>(1)
  end

  defp valid_human_timeout?(value) when is_integer(value), do: value > 0

  defp valid_human_timeout?(value) when is_binary(value) do
    trimmed = String.trim(value)

    case Integer.parse(trimmed) do
      {parsed, ""} ->
        parsed > 0

      _ ->
        case Regex.run(~r/^(\d+)(ms|s|m|h|d)$/, trimmed, capture: :all_but_first) do
          [amount, _unit] -> String.to_integer(amount) > 0
          _ -> false
        end
    end
  end

  defp valid_human_timeout?(_value), do: false

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
