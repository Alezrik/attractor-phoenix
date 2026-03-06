defmodule AttractorEx.Engine do
  @moduledoc false

  alias AttractorEx.{
    Checkpoint,
    Condition,
    Graph,
    HandlerRegistry,
    Outcome,
    Parser,
    Validator
  }

  def run(dot, initial_context, opts \\ []) do
    normalized_initial_context = normalize_context(initial_context)

    with {:ok, %Graph{} = graph} <- Parser.parse(dot),
         diagnostics <- Validator.validate(graph),
         [] <- Enum.filter(diagnostics, &(&1.severity == :error)) do
      execute(
        graph,
        normalized_initial_context,
        diagnostics,
        Keyword.put(opts, :_initial_context, normalized_initial_context)
      )
    else
      {:error, reason} -> {:error, %{error: reason}}
      errors when is_list(errors) -> {:error, %{diagnostics: errors}}
    end
  end

  defp execute(graph, initial_context, diagnostics, opts) do
    run_id = Keyword.get(opts, :run_id, Integer.to_string(System.unique_integer([:positive])))
    run_root = Path.join(Keyword.get(opts, :logs_root, Path.join(["tmp", "runs"])), run_id)
    max_steps = Keyword.get(opts, :max_steps, 500)
    start_override = Keyword.get(opts, :start_at)

    _ = File.mkdir_p(run_root)

    _ =
      write_json(Path.join(run_root, "manifest.json"), %{
        graph: graph.id,
        run_id: run_id,
        goal: graph.attrs["goal"]
      })

    start_id = start_override || Validator.start_node_id(graph)

    context =
      initial_context
      |> Map.put_new("run_id", run_id)
      |> Map.put_new("graph", %{"goal" => Map.get(graph.attrs, "goal", "")})

    case start_id do
      nil ->
        {:error,
         %{diagnostics: [%{severity: :error, code: :start_node, message: "Start node missing"}]}}

      id ->
        loop(graph, id, context, %{}, [], run_root, diagnostics, max_steps, opts)
    end
  end

  defp loop(_graph, _node_id, context, outcomes, history, run_root, diagnostics, 0, _opts) do
    final = %{
      run_id: context["run_id"],
      status: :fail,
      reason: "Max steps exceeded",
      context: context,
      outcomes: normalize_outcomes(outcomes),
      history: history,
      logs_root: run_root,
      diagnostics: diagnostics
    }

    {:ok, final}
  end

  defp loop(graph, node_id, context, outcomes, history, run_root, diagnostics, steps_left, opts) do
    node = Map.fetch!(graph.nodes, node_id)
    retry_policy = build_retry_policy(node, graph, opts)
    {outcome, stage_dir} = execute_with_retry(node, context, graph, run_root, retry_policy, opts)
    _ = write_json(Path.join(stage_dir, "status.json"), serialize_outcome(outcome))

    next_context =
      context
      |> deep_merge(normalize_context(outcome.context_updates))
      |> Map.put("outcome", Atom.to_string(outcome.status))
      |> maybe_put("preferred_label", outcome.preferred_label)
      |> maybe_put("suggested_next_ids", outcome.suggested_next_ids)

    next_outcomes = Map.put(outcomes, node.id, outcome)
    next_history = history ++ [%{node_id: node.id, status: outcome.status}]

    checkpoint = Checkpoint.new(node.id, Map.keys(next_outcomes), next_context)
    _ = write_json(Path.join(run_root, "checkpoint.json"), Map.from_struct(checkpoint))

    if node.type == "exit" do
      case pick_retry_target(graph, next_outcomes) do
        nil ->
          status = if all_goal_gates_satisfied?(graph, next_outcomes), do: :success, else: :fail

          reason =
            if status == :fail and not all_goal_gates_satisfied?(graph, next_outcomes),
              do: "Goal gate unsatisfied and no retry target",
              else: nil

          {:ok,
           %{
             run_id: next_context["run_id"],
             status: status,
             reason: reason,
             context: next_context,
             outcomes: normalize_outcomes(next_outcomes),
             history: next_history,
             logs_root: run_root,
             diagnostics: diagnostics
           }}

        retry_target ->
          if Map.has_key?(graph.nodes, retry_target) do
            loop(
              graph,
              retry_target,
              next_context,
              next_outcomes,
              next_history,
              run_root,
              diagnostics,
              steps_left - 1,
              opts
            )
          else
            {:ok,
             %{
               run_id: next_context["run_id"],
               status: :fail,
               reason: "Retry target `#{retry_target}` not found",
               context: next_context,
               outcomes: normalize_outcomes(next_outcomes),
               history: next_history,
               logs_root: run_root,
               diagnostics: diagnostics
             }}
          end
      end
    else
      case select_next_edge(graph, node.id, next_context, outcome) do
        nil ->
          case failure_route_target(node, graph, outcome.status) do
            nil ->
              reason =
                if outcome.status == :fail do
                  outcome.failure_reason || "Stage failed with no outgoing fail edge"
                else
                  "No outgoing edge selected from node `#{node.id}`"
                end

              {:ok,
               %{
                 run_id: next_context["run_id"],
                 status: :fail,
                 reason: reason,
                 context: next_context,
                 outcomes: normalize_outcomes(next_outcomes),
                 history: next_history,
                 logs_root: run_root,
                 diagnostics: diagnostics
               }}

            target ->
              loop(
                graph,
                target,
                next_context,
                next_outcomes,
                next_history,
                run_root,
                diagnostics,
                steps_left - 1,
                opts
              )
          end

        edge ->
          if edge_loop_restart?(edge) do
            restart_opts =
              opts
              |> Keyword.delete(:run_id)
              |> Keyword.put(:start_at, edge.to)

            execute(graph, Keyword.get(opts, :_initial_context, %{}), diagnostics, restart_opts)
          else
            loop(
              graph,
              edge.to,
              next_context,
              next_outcomes,
              next_history,
              run_root,
              diagnostics,
              steps_left - 1,
              opts
            )
          end
      end
    end
  end

  defp execute_node(node, context, graph, stage_dir, opts) do
    handler = HandlerRegistry.handler_for(node)

    case handler.execute(node, context, graph, stage_dir, opts) do
      %Outcome{} = outcome -> outcome
      _ -> Outcome.fail("Handler returned invalid outcome")
    end
  rescue
    error -> Outcome.fail("Handler exception: #{Exception.message(error)}")
  end

  defp execute_with_retry(node, context, graph, run_root, retry_policy, opts) do
    Enum.reduce_while(
      1..retry_policy.max_attempts,
      {Outcome.fail("max retries exceeded"), nil},
      fn attempt, _acc ->
        stage_dir = stage_dir_for_attempt(run_root, node.id, attempt)
        _ = File.mkdir_p(stage_dir)

        outcome =
          try do
            execute_node(node, context, graph, stage_dir, opts)
          rescue
            error ->
              if retry_policy.should_retry.(error) and attempt < retry_policy.max_attempts do
                delay = retry_delay_ms(retry_policy.backoff, attempt)
                maybe_sleep(delay, opts)
                :retry_exception
              else
                Outcome.fail(Exception.message(error))
              end
          end

        cond do
          outcome == :retry_exception ->
            _ =
              write_json(
                Path.join(stage_dir, "status.json"),
                serialize_outcome(Outcome.retry("retrying after exception"))
              )

            {:cont, {Outcome.fail("retrying after exception"), stage_dir}}

          outcome.status in [:success, :partial_success] ->
            _ = write_json(Path.join(stage_dir, "status.json"), serialize_outcome(outcome))
            {:halt, {outcome, stage_dir}}

          outcome.status == :retry and attempt < retry_policy.max_attempts ->
            _ = write_json(Path.join(stage_dir, "status.json"), serialize_outcome(outcome))
            delay = retry_delay_ms(retry_policy.backoff, attempt)
            maybe_sleep(delay, opts)
            {:cont, {outcome, stage_dir}}

          outcome.status == :retry and node_allows_partial?(node) ->
            final = Outcome.partial_success(%{}, "retries exhausted, partial accepted")
            _ = write_json(Path.join(stage_dir, "status.json"), serialize_outcome(final))
            {:halt, {final, stage_dir}}

          outcome.status == :retry ->
            final = Outcome.fail("max retries exceeded")
            _ = write_json(Path.join(stage_dir, "status.json"), serialize_outcome(final))
            {:halt, {final, stage_dir}}

          outcome.status == :fail ->
            _ = write_json(Path.join(stage_dir, "status.json"), serialize_outcome(outcome))
            {:halt, {outcome, stage_dir}}

          true ->
            _ = write_json(Path.join(stage_dir, "status.json"), serialize_outcome(outcome))
            {:halt, {outcome, stage_dir}}
        end
      end
    )
  end

  defp select_next_edge(graph, node_id, context, outcome) do
    outgoing = Enum.filter(graph.edges, &(&1.from == node_id))

    if outgoing == [] do
      nil
    else
      condition_matched =
        Enum.filter(outgoing, fn edge ->
          is_binary(edge.condition) and condition_matches?(edge.condition, context, outcome)
        end)

      if condition_matched != [] do
        best_by_weight_then_lexical(condition_matched)
      else
        status_matched =
          Enum.filter(outgoing, fn edge ->
            is_binary(edge.status) and
              String.downcase(edge.status) == Atom.to_string(outcome.status)
          end)

        if status_matched != [] do
          best_by_weight_then_lexical(status_matched)
        else
          with nil <- select_by_preferred_label(outgoing, outcome),
               nil <- select_by_suggested_ids(outgoing, outcome),
               nil <- select_unconditional_by_weight(outgoing) do
            best_by_weight_then_lexical(outgoing)
          end
        end
      end
    end
  end

  defp condition_matches?(condition, context, outcome) do
    outcome_status = Atom.to_string(outcome.status)
    enriched_context = Map.put(context, "outcome", %{"status" => outcome_status})
    match?({:ok, true}, Condition.evaluate(condition, enriched_context))
  end

  defp select_by_preferred_label(edges, outcome) do
    if is_binary(outcome.preferred_label) and String.trim(outcome.preferred_label) != "" do
      normalized_preferred = normalize_label(outcome.preferred_label)

      edges
      |> Enum.filter(fn edge -> is_nil(edge.condition) or edge.condition == "" end)
      |> Enum.find(fn edge ->
        normalize_label(Map.get(edge.attrs, "label", "")) == normalized_preferred
      end)
    else
      nil
    end
  end

  defp select_by_suggested_ids(edges, outcome) do
    suggested = outcome.suggested_next_ids || []
    Enum.find_value(suggested, fn id -> Enum.find(edges, &(&1.to == id)) end)
  end

  defp select_unconditional_by_weight(edges) do
    unconditional =
      Enum.filter(edges, fn edge ->
        (is_nil(edge.condition) or edge.condition == "") and
          (is_nil(edge.status) or edge.status == "")
      end)

    if unconditional == [], do: nil, else: best_by_weight_then_lexical(unconditional)
  end

  defp best_by_weight_then_lexical(edges) do
    edges
    |> Enum.sort_by(fn edge -> {-edge_weight(edge), edge.to} end)
    |> List.first()
  end

  defp edge_weight(edge) do
    case Map.get(edge.attrs, "weight", 0) do
      weight when is_integer(weight) -> weight
      weight when is_float(weight) -> trunc(weight)
      weight when is_binary(weight) -> String.to_integer(weight)
      _ -> 0
    end
  rescue
    _ -> 0
  end

  defp normalize_label(label) do
    label
    |> to_string()
    |> String.downcase()
    |> String.trim()
    |> String.replace(~r/^\[[a-z0-9]+\]\s*/, "")
    |> String.replace(~r/^[a-z0-9]+\)\s*/, "")
    |> String.replace(~r/^[a-z0-9]+\s*-\s*/, "")
  end

  defp pick_retry_target(graph, outcomes) do
    unsatisfied_gate =
      graph.nodes
      |> Enum.find_value(fn {_id, node} ->
        if node.goal_gate do
          case Map.get(outcomes, node.id) do
            %Outcome{status: status} when status in [:success, :partial_success] -> nil
            _ -> node
          end
        end
      end)

    if is_nil(unsatisfied_gate) do
      nil
    else
      unsatisfied_gate.retry_target ||
        unsatisfied_gate.fallback_retry_target ||
        graph.attrs["retry_target"] ||
        graph.attrs["fallback_retry_target"]
    end
  end

  defp failure_route_target(node, graph, :fail) do
    node.retry_target || node.fallback_retry_target || graph.attrs["retry_target"] ||
      graph.attrs["fallback_retry_target"]
  end

  defp failure_route_target(_node, _graph, _status), do: nil

  defp edge_loop_restart?(edge) do
    value = Map.get(edge.attrs, "loop_restart", false)
    value == true or (is_binary(value) and String.downcase(value) == "true")
  end

  defp build_retry_policy(node, graph, opts) do
    max_retries =
      cond do
        is_integer(node.attrs["max_retries"]) ->
          node.attrs["max_retries"]

        is_binary(node.attrs["max_retries"]) ->
          String.to_integer(node.attrs["max_retries"])

        is_integer(graph.attrs["default_max_retry"]) ->
          graph.attrs["default_max_retry"]

        is_binary(graph.attrs["default_max_retry"]) ->
          String.to_integer(graph.attrs["default_max_retry"])

        true ->
          0
      end

    max_attempts = max(1, max_retries + 1)

    backoff = %{
      initial_delay_ms: Keyword.get(opts, :initial_delay_ms, 200),
      backoff_factor: Keyword.get(opts, :backoff_factor, 2.0),
      max_delay_ms: Keyword.get(opts, :max_delay_ms, 60_000),
      jitter: Keyword.get(opts, :retry_jitter, true)
    }

    should_retry =
      Keyword.get(opts, :should_retry, fn _error ->
        true
      end)

    %{max_attempts: max_attempts, backoff: backoff, should_retry: should_retry}
  rescue
    _ ->
      %{
        max_attempts: 1,
        backoff: %{initial_delay_ms: 0, backoff_factor: 1.0, max_delay_ms: 0, jitter: false},
        should_retry: fn _ -> false end
      }
  end

  defp retry_delay_ms(backoff, attempt) do
    delay =
      (backoff.initial_delay_ms * :math.pow(backoff.backoff_factor, attempt - 1))
      |> trunc()
      |> min(backoff.max_delay_ms)

    if backoff.jitter do
      (delay * (:rand.uniform() + 0.5)) |> trunc()
    else
      delay
    end
  end

  defp maybe_sleep(delay_ms, opts) do
    if Keyword.get(opts, :retry_sleep, false) and delay_ms > 0 do
      Process.sleep(delay_ms)
    end
  end

  defp node_allows_partial?(node) do
    value = node.attrs["allow_partial"]
    value == true or (is_binary(value) and String.downcase(value) == "true")
  end

  defp stage_dir_for_attempt(run_root, node_id, 1), do: Path.join(run_root, node_id)

  defp stage_dir_for_attempt(run_root, node_id, attempt),
    do: Path.join(run_root, "#{node_id}_attempt_#{attempt}")

  defp all_goal_gates_satisfied?(graph, outcomes) do
    Enum.all?(graph.nodes, fn {_id, node} ->
      if node.goal_gate do
        case Map.get(outcomes, node.id) do
          %Outcome{status: status} -> status in [:success, :partial_success]
          _ -> false
        end
      else
        true
      end
    end)
  end

  defp serialize_outcome(outcome) do
    %{
      status: outcome.status,
      notes: outcome.notes,
      failure_reason: outcome.failure_reason,
      context_updates: outcome.context_updates,
      preferred_label: outcome.preferred_label,
      suggested_next_ids: outcome.suggested_next_ids
    }
  end

  defp normalize_outcomes(outcomes) do
    outcomes
    |> Enum.map(fn {id, outcome} -> {id, serialize_outcome(outcome)} end)
    |> Map.new()
  end

  defp normalize_context(value) when is_map(value) do
    value
    |> Enum.map(fn {k, v} -> {to_string(k), normalize_context(v)} end)
    |> Map.new()
  end

  defp normalize_context(value) when is_list(value), do: Enum.map(value, &normalize_context/1)
  defp normalize_context(value), do: value

  defp deep_merge(lhs, rhs) when is_map(lhs) and is_map(rhs) do
    Map.merge(lhs, rhs, fn _k, left, right ->
      if is_map(left) and is_map(right), do: deep_merge(left, right), else: right
    end)
  end

  defp deep_merge(_lhs, rhs), do: rhs

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, _key, []), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp write_json(path, value) do
    with {:ok, encoded} <- Jason.encode(value, pretty: true) do
      File.write(path, encoded)
    end
  end
end
