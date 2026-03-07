defmodule AttractorEx.Engine do
  @moduledoc false

  alias AttractorEx.{
    Checkpoint,
    Condition,
    Graph,
    HandlerRegistry,
    Outcome,
    Parser,
    StatusContract,
    Transforms.VariableExpansion,
    Validator
  }

  def run(dot, initial_context, opts \\ []) do
    with {:ok, %Graph{} = graph} <- Parser.parse(dot),
         {:ok, %Graph{} = transformed_graph} <- apply_graph_transforms(graph, opts),
         diagnostics <- Validator.validate(transformed_graph),
         [] <- Enum.filter(diagnostics, &(&1.severity == :error)) do
      normalized_initial_context = normalize_context(initial_context)

      execute(
        transformed_graph,
        normalized_initial_context,
        diagnostics,
        Keyword.put(opts, :_initial_context, normalized_initial_context)
      )
    else
      {:error, reason} -> {:error, %{error: reason, error_category: "pipeline"}}
      errors when is_list(errors) -> {:error, %{diagnostics: errors, error_category: "pipeline"}}
    end
  end

  def resume(dot, checkpoint_or_path, opts \\ []) do
    with {:ok, %Graph{} = graph} <- Parser.parse(dot),
         {:ok, %Graph{} = transformed_graph} <- apply_graph_transforms(graph, opts),
         diagnostics <- Validator.validate(transformed_graph),
         [] <- Enum.filter(diagnostics, &(&1.severity == :error)),
         {:ok, checkpoint, inferred_opts} <- load_checkpoint(checkpoint_or_path) do
      checkpoint_context = normalize_context(checkpoint.context)

      resume_opts =
        opts
        |> Keyword.merge(inferred_opts)
        |> Keyword.put_new(:start_at, checkpoint.current_node)
        |> maybe_put_run_id(checkpoint_context)

      execute(
        transformed_graph,
        checkpoint_context,
        diagnostics,
        Keyword.put(resume_opts, :_initial_context, checkpoint_context)
      )
    else
      {:error, reason} when is_binary(reason) ->
        {:error, %{error: reason, error_category: "pipeline"}}

      {:error, %{error: _} = error} ->
        {:error, error}

      errors when is_list(errors) ->
        {:error, %{diagnostics: errors, error_category: "pipeline"}}
    end
  end

  defp load_checkpoint(path) when is_binary(path) do
    checkpoint_path = Path.expand(path)

    with {:ok, contents} <- File.read(checkpoint_path),
         {:ok, decoded} <- Jason.decode(contents),
         checkpoint <- normalize_checkpoint(decoded) do
      run_root = Path.dirname(checkpoint_path)
      inferred_opts = [logs_root: Path.dirname(run_root), run_id: Path.basename(run_root)]
      {:ok, checkpoint, inferred_opts}
    else
      {:error, :enoent} ->
        {:error,
         %{error: "Checkpoint file not found: #{checkpoint_path}", error_category: "pipeline"}}

      {:error, reason} ->
        {:error,
         %{error: "Checkpoint read/decode failed: #{inspect(reason)}", error_category: "pipeline"}}
    end
  end

  defp load_checkpoint(%Checkpoint{} = checkpoint), do: {:ok, checkpoint, []}

  defp load_checkpoint(checkpoint) when is_map(checkpoint),
    do: {:ok, normalize_checkpoint(checkpoint), []}

  defp load_checkpoint(_value),
    do:
      {:error,
       %{
         error: "Checkpoint must be a file path, map, or %AttractorEx.Checkpoint{}",
         error_category: "pipeline"
       }}

  defp normalize_checkpoint(checkpoint) do
    %Checkpoint{
      timestamp: Map.get(checkpoint, "timestamp") || Map.get(checkpoint, :timestamp),
      current_node: Map.get(checkpoint, "current_node") || Map.get(checkpoint, :current_node),
      completed_nodes:
        Map.get(checkpoint, "completed_nodes") || Map.get(checkpoint, :completed_nodes) || [],
      context: Map.get(checkpoint, "context") || Map.get(checkpoint, :context) || %{}
    }
  end

  defp maybe_put_run_id(opts, context) do
    case Map.get(context, "run_id") do
      run_id when is_binary(run_id) and run_id != "" -> Keyword.put_new(opts, :run_id, run_id)
      _ -> opts
    end
  end

  defp apply_graph_transforms(%Graph{} = graph, opts) do
    transforms = normalized_graph_transforms(opts)

    Enum.reduce_while(transforms, {:ok, graph}, fn transform, {:ok, current_graph} ->
      case apply_graph_transform(transform, current_graph) do
        {:ok, %Graph{} = next_graph} -> {:cont, {:ok, next_graph}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp normalized_graph_transforms(opts) do
    transforms = [VariableExpansion | List.wrap(Keyword.get(opts, :graph_transforms, []))]
    legacy_transform = Keyword.get(opts, :graph_transform)

    if is_nil(legacy_transform), do: transforms, else: transforms ++ [legacy_transform]
  end

  defp apply_graph_transform(transform, %Graph{} = graph) when is_function(transform, 1) do
    safe_graph_transform(transform, graph)
  end

  defp apply_graph_transform(transform, %Graph{} = graph) when is_atom(transform) do
    cond do
      Code.ensure_loaded?(transform) and function_exported?(transform, :apply, 1) ->
        safe_graph_transform(fn value -> transform.apply(value) end, graph)

      Code.ensure_loaded?(transform) and function_exported?(transform, :transform, 1) ->
        safe_graph_transform(fn value -> transform.transform(value) end, graph)

      true ->
        {:error,
         "Invalid graph transform: expected function/1 or module with apply/1 or transform/1"}
    end
  end

  defp apply_graph_transform(_transform, _graph) do
    {:error, "Invalid graph transform: expected function/1 or module with apply/1 or transform/1"}
  end

  defp safe_graph_transform(transform_fun, %Graph{} = graph) do
    case transform_fun.(graph) do
      %Graph{} = transformed ->
        {:ok, transformed}

      _other ->
        {:error, "Graph transform must return %AttractorEx.Graph{}"}
    end
  rescue
    error ->
      {:error, "Graph transform failed: #{Exception.message(error)}"}
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
      |> Map.put_new("graph", normalize_context(graph.attrs))

    emit_event(opts, %{
      type: "PipelineStarted",
      id: run_id,
      name: graph.id,
      context: context
    })

    case start_id do
      nil ->
        {:error,
         %{diagnostics: [%{severity: :error, code: :start_node, message: "Start node missing"}]}}

      id ->
        loop(graph, id, context, %{}, [], run_root, diagnostics, max_steps, opts, nil)
    end
  end

  defp loop(
         _graph,
         _node_id,
         context,
         outcomes,
         history,
         run_root,
         diagnostics,
         0,
         opts,
         _incoming_edge
       ) do
    final = %{
      run_id: context["run_id"],
      status: :fail,
      reason: "Max steps exceeded",
      error_category: :pipeline,
      context: context,
      outcomes: normalize_outcomes(outcomes),
      history: history,
      logs_root: run_root,
      diagnostics: diagnostics
    }

    emit_pipeline_terminal_event(final, "PipelineFailed", %{error: final.reason}, opts)
    {:ok, final}
  end

  defp loop(
         graph,
         node_id,
         context,
         outcomes,
         history,
         run_root,
         diagnostics,
         steps_left,
         opts,
         incoming_edge
       ) do
    node = Map.fetch!(graph.nodes, node_id)

    runtime_node =
      apply_runtime_transforms(node, graph, context, outcomes, history, incoming_edge)

    context = Map.put(context, "current_node", node.id)
    retry_policy = build_retry_policy(node, graph, opts)
    stage_index = length(history)

    emit_event(opts, %{
      type: "StageStarted",
      name: node.id,
      index: stage_index,
      context: context
    })

    {outcome, stage_dir} =
      execute_with_retry(runtime_node, context, graph, run_root, retry_policy, opts)

    _ = StatusContract.write_status_file(Path.join(stage_dir, "status.json"), outcome)

    next_context =
      context
      |> deep_merge(normalize_context(outcome.context_updates))
      |> Map.put("outcome", Atom.to_string(outcome.status))
      |> maybe_put("preferred_label", outcome.preferred_label)
      |> maybe_put("preferred_next_label", outcome.preferred_label)
      |> maybe_put("suggested_next_ids", outcome.suggested_next_ids)

    next_outcomes = Map.put(outcomes, node.id, outcome)
    next_history = history ++ [%{node_id: node.id, status: outcome.status}]

    checkpoint = Checkpoint.new(node.id, Map.keys(next_outcomes), next_context)
    _ = write_json(Path.join(run_root, "checkpoint.json"), Map.from_struct(checkpoint))

    emit_event(opts, %{
      type: "CheckpointSaved",
      node_id: node.id,
      checkpoint: Map.from_struct(checkpoint),
      context: next_context
    })

    emit_stage_outcome_event(opts, node, outcome, stage_index, next_context)

    if node.type == "exit" do
      handle_exit_node(
        graph,
        next_context,
        next_outcomes,
        next_history,
        run_root,
        diagnostics,
        steps_left,
        opts,
        incoming_edge
      )
    else
      handle_non_exit_node(
        graph,
        node,
        outcome,
        next_context,
        next_outcomes,
        next_history,
        run_root,
        diagnostics,
        steps_left,
        opts
      )
    end
  end

  defp emit_stage_outcome_event(opts, node, outcome, stage_index, context) do
    case outcome.status do
      status when status in [:success, :partial_success] ->
        emit_event(opts, %{
          type: "StageCompleted",
          name: node.id,
          index: stage_index,
          status: Atom.to_string(status),
          context: context
        })

      :fail ->
        emit_event(opts, %{
          type: "StageFailed",
          name: node.id,
          index: stage_index,
          error: outcome.failure_reason,
          error_category: normalize_failure_category(outcome.failure_category),
          will_retry: false,
          status: "fail",
          context: context
        })

      _ ->
        :ok
    end
  end

  defp handle_exit_node(
         graph,
         context,
         outcomes,
         history,
         run_root,
         diagnostics,
         steps_left,
         opts,
         incoming_edge
       ) do
    case pick_retry_target(graph, outcomes) do
      nil ->
        status = if all_goal_gates_satisfied?(graph, outcomes), do: :success, else: :fail

        reason =
          if status == :fail and not all_goal_gates_satisfied?(graph, outcomes),
            do: "Goal gate unsatisfied and no retry target",
            else: nil

        terminal_result(status, reason, context, outcomes, history, run_root, diagnostics, opts)

      retry_target ->
        if Map.has_key?(graph.nodes, retry_target) do
          loop(
            graph,
            retry_target,
            context,
            outcomes,
            history,
            run_root,
            diagnostics,
            steps_left - 1,
            opts,
            incoming_edge
          )
        else
          terminal_result(
            :fail,
            "Retry target `#{retry_target}` not found",
            context,
            outcomes,
            history,
            run_root,
            diagnostics,
            opts
          )
        end
    end
  end

  defp handle_non_exit_node(
         graph,
         node,
         outcome,
         context,
         outcomes,
         history,
         run_root,
         diagnostics,
         steps_left,
         opts
       ) do
    case select_next_edge(graph, node.id, context, outcome) do
      nil ->
        case failure_route_target(node, graph, outcome.status) do
          nil ->
            reason =
              if outcome.status == :fail do
                outcome.failure_reason || "Stage failed with no outgoing fail edge"
              else
                "No outgoing edge selected from node `#{node.id}`"
              end

            terminal_result(
              :fail,
              reason,
              context,
              outcomes,
              history,
              run_root,
              diagnostics,
              opts
            )

          target ->
            loop(
              graph,
              target,
              context,
              outcomes,
              history,
              run_root,
              diagnostics,
              steps_left - 1,
              opts,
              nil
            )
        end

      edge ->
        continue_from_edge(
          graph,
          edge,
          context,
          outcomes,
          history,
          run_root,
          diagnostics,
          steps_left,
          opts
        )
    end
  end

  defp continue_from_edge(
         graph,
         edge,
         context,
         outcomes,
         history,
         run_root,
         diagnostics,
         steps_left,
         opts
       ) do
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
        context,
        outcomes,
        history,
        run_root,
        diagnostics,
        steps_left - 1,
        opts,
        edge
      )
    end
  end

  defp apply_runtime_transforms(node, graph, context, outcomes, history, incoming_edge) do
    if HandlerRegistry.handler_for(node) == AttractorEx.Handlers.Codergen do
      maybe_apply_preamble_transform(node, graph, context, outcomes, history, incoming_edge)
    else
      node
    end
  end

  defp maybe_apply_preamble_transform(node, graph, context, outcomes, history, incoming_edge) do
    prompt = blank_to_nil(node.prompt) || blank_to_nil(node.attrs["label"])
    fidelity = resolve_fidelity(node, graph, incoming_edge)

    cond do
      is_nil(prompt) ->
        node

      fidelity == "full" ->
        node

      true ->
        preamble = build_preamble(graph, context, outcomes, history, fidelity)

        if is_nil(preamble) do
          node
        else
          merged_prompt = preamble <> "\n\n" <> prompt
          %{node | prompt: merged_prompt, attrs: Map.put(node.attrs, "prompt", merged_prompt)}
        end
    end
  end

  defp resolve_fidelity(node, graph, incoming_edge) do
    blank_to_nil(incoming_edge && incoming_edge.attrs["fidelity"]) ||
      blank_to_nil(node.attrs["fidelity"]) ||
      blank_to_nil(graph.attrs["default_fidelity"]) ||
      "compact"
  end

  defp build_preamble(graph, context, outcomes, history, fidelity) do
    if meaningful_carryover?(context, outcomes, history) do
      sections =
        [
          "Context carryover (#{fidelity}):",
          preamble_goal(graph),
          preamble_run_id(context),
          preamble_history(history, fidelity),
          preamble_outcomes(outcomes, fidelity),
          preamble_context(context, fidelity)
        ]
        |> Enum.reject(&is_nil/1)

      if length(sections) <= 1, do: nil, else: Enum.join(sections, "\n")
    else
      nil
    end
  end

  defp meaningful_carryover?(context, outcomes, history) do
    non_system_context?(context) or
      Enum.any?(history, &(&1.node_id != "start")) or
      Enum.any?(outcomes, fn {node_id, _outcome} -> node_id != "start" end)
  end

  defp non_system_context?(context) do
    context
    |> Map.drop(["current_node", "graph", "outcome", "responses", "run_id"])
    |> map_size()
    |> Kernel.>(0)
  end

  defp preamble_goal(graph) do
    case blank_to_nil(graph.attrs["goal"]) do
      nil -> nil
      goal -> "Goal: #{goal}"
    end
  end

  defp preamble_run_id(context) do
    case blank_to_nil(context["run_id"]) do
      nil -> nil
      run_id -> "Run ID: #{run_id}"
    end
  end

  defp preamble_history(_history, "truncate"), do: nil

  defp preamble_history(history, fidelity) do
    entries =
      history
      |> Enum.take(-history_limit(fidelity))
      |> Enum.map(fn %{node_id: node_id, status: status} ->
        "- #{node_id} [status=#{status}]"
      end)

    if entries == [], do: nil, else: Enum.join(["Completed stages:" | entries], "\n")
  end

  defp preamble_outcomes(_outcomes, fidelity) when fidelity in ["truncate", "compact"], do: nil

  defp preamble_outcomes(outcomes, fidelity) do
    entries =
      outcomes
      |> Enum.sort_by(fn {node_id, _outcome} -> node_id end)
      |> Enum.take(-outcome_limit(fidelity))
      |> Enum.map(fn {node_id, outcome} ->
        status = Map.get(outcome, :status) || Map.get(outcome, "status")
        note = blank_to_nil(Map.get(outcome, :notes) || Map.get(outcome, "notes"))

        if is_nil(note) do
          "- #{node_id}: #{status}"
        else
          "- #{node_id}: #{status} (#{note})"
        end
      end)

    if entries == [], do: nil, else: Enum.join(["Recent outcomes:" | entries], "\n")
  end

  defp preamble_context(context, fidelity) do
    entries =
      context
      |> Map.drop(["current_node", "graph", "outcome", "responses", "run_id"])
      |> Enum.sort_by(fn {key, _value} -> key end)
      |> Enum.take(context_limit(fidelity))
      |> Enum.map(fn {key, value} -> "- #{key}: #{format_context_value(value)}" end)

    if entries == [], do: nil, else: Enum.join(["Context values:" | entries], "\n")
  end

  defp history_limit("compact"), do: 4
  defp history_limit("summary:low"), do: 4
  defp history_limit("summary:medium"), do: 8
  defp history_limit("summary:high"), do: 12
  defp history_limit(_fidelity), do: 4

  defp outcome_limit("summary:low"), do: 3
  defp outcome_limit("summary:medium"), do: 6
  defp outcome_limit("summary:high"), do: 10
  defp outcome_limit(_fidelity), do: 0

  defp context_limit("truncate"), do: 0
  defp context_limit("compact"), do: 4
  defp context_limit("summary:low"), do: 4
  defp context_limit("summary:medium"), do: 8
  defp context_limit("summary:high"), do: 12
  defp context_limit(_fidelity), do: 4

  defp format_context_value(value) when is_binary(value), do: inspect(value)
  defp format_context_value(value), do: inspect(value, printable_limit: 120)

  defp terminal_result(status, reason, context, outcomes, history, run_root, diagnostics, opts) do
    final = %{
      run_id: context["run_id"],
      status: status,
      reason: reason,
      error_category: final_error_category(status, reason, outcomes),
      context: context,
      outcomes: normalize_outcomes(outcomes),
      history: history,
      logs_root: run_root,
      diagnostics: diagnostics
    }

    event_type = if status == :success, do: "PipelineCompleted", else: "PipelineFailed"
    emit_pipeline_terminal_event(final, event_type, %{error: final.reason}, opts)
    {:ok, final}
  end

  defp execute_node(node, context, graph, stage_dir, opts) do
    handler = HandlerRegistry.handler_for(node)

    case handler.execute(node, context, graph, stage_dir, opts) do
      %Outcome{} = outcome -> outcome
      _ -> Outcome.fail("Handler returned invalid outcome", :pipeline)
    end
  rescue
    error -> Outcome.fail("Handler exception: #{Exception.message(error)}", :terminal)
  end

  defp execute_with_retry(node, context, graph, run_root, retry_policy, opts) do
    Enum.reduce_while(
      1..retry_policy.max_attempts,
      {Outcome.fail("max retries exceeded", :retryable), nil},
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
                Outcome.fail(Exception.message(error), :terminal)
              end
          end

        cond do
          outcome == :retry_exception ->
            _ =
              StatusContract.write_status_file(
                Path.join(stage_dir, "status.json"),
                Outcome.retry("retrying after exception", :retryable)
              )

            {:cont, {Outcome.fail("retrying after exception", :retryable), stage_dir}}

          outcome.status in [:success, :partial_success] ->
            _ = StatusContract.write_status_file(Path.join(stage_dir, "status.json"), outcome)
            {:halt, {outcome, stage_dir}}

          outcome.status == :retry and attempt < retry_policy.max_attempts ->
            _ = StatusContract.write_status_file(Path.join(stage_dir, "status.json"), outcome)
            delay = retry_delay_ms(retry_policy.backoff, attempt)

            emit_event(opts, %{
              type: "StageRetrying",
              name: node.id,
              index: nil,
              attempt: attempt,
              delay_ms: delay,
              error_category: normalize_failure_category(outcome.failure_category)
            })

            maybe_sleep(delay, opts)
            {:cont, {outcome, stage_dir}}

          outcome.status == :retry and node_allows_partial?(node) ->
            final = Outcome.partial_success(%{}, "retries exhausted, partial accepted")
            _ = StatusContract.write_status_file(Path.join(stage_dir, "status.json"), final)
            {:halt, {final, stage_dir}}

          outcome.status == :retry ->
            final = Outcome.fail("max retries exceeded", :retryable)
            _ = StatusContract.write_status_file(Path.join(stage_dir, "status.json"), final)
            {:halt, {final, stage_dir}}

          outcome.status == :fail ->
            _ = StatusContract.write_status_file(Path.join(stage_dir, "status.json"), outcome)
            {:halt, {outcome, stage_dir}}

          true ->
            _ = StatusContract.write_status_file(Path.join(stage_dir, "status.json"), outcome)
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
          50
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

  defp normalize_outcomes(outcomes) do
    outcomes
    |> Enum.map(fn {id, outcome} -> {id, StatusContract.serialize_outcome(outcome)} end)
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

  defp blank_to_nil(nil), do: nil

  defp blank_to_nil(value) do
    trimmed = value |> to_string() |> String.trim()
    if trimmed == "", do: nil, else: trimmed
  end

  defp write_json(path, value) do
    with {:ok, encoded} <- Jason.encode(value, pretty: true) do
      File.write(path, encoded)
    end
  end

  defp emit_event(opts, event) do
    case Keyword.get(opts, :event_observer) do
      fun when is_function(fun, 1) -> fun.(event)
      _ -> :ok
    end
  end

  defp emit_pipeline_terminal_event(final, type, extra, opts) do
    emit_event(
      opts,
      %{
        type: type,
        status: Atom.to_string(final.status),
        pipeline_id: final.run_id,
        error_category: normalize_failure_category(final.error_category),
        context: final.context
      }
      |> Map.merge(extra)
    )
  end

  defp final_error_category(:success, _reason, _outcomes), do: nil
  defp final_error_category(_status, nil, _outcomes), do: nil

  defp final_error_category(_status, reason, outcomes) do
    reason_text = to_string(reason)

    cond do
      reason_text in ["Max steps exceeded", "Goal gate unsatisfied and no retry target"] ->
        :pipeline

      String.contains?(reason_text, "Retry target `") ->
        :pipeline

      String.contains?(reason_text, "No outgoing edge selected") ->
        :pipeline

      String.contains?(reason_text, "Stage failed with no outgoing fail edge") ->
        :pipeline

      true ->
        last_failure_category(outcomes) || :terminal
    end
  end

  defp last_failure_category(outcomes) do
    outcomes
    |> Enum.reverse()
    |> Enum.find_value(fn {_node_id, outcome} ->
      if outcome.status in [:fail, :retry], do: outcome.failure_category, else: nil
    end)
  end

  defp normalize_failure_category(nil), do: nil
  defp normalize_failure_category(category), do: Atom.to_string(category)
end
