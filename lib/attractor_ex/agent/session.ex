defmodule AttractorEx.Agent.Session do
  @moduledoc """
  Stateful coding-agent loop built on top of `AttractorEx.LLM.Client`.

  A session owns request construction, conversation history, tool execution, tool
  result truncation, steering and follow-up queues, loop detection, subagent
  lifecycle management, lifecycle events, and layered project-instruction discovery
  across ancestor `AGENTS.md`/provider-specific docs with a shared 32 KB prompt budget.
  """

  alias AttractorEx.Agent.{
    Event,
    ExecutionEnvironment,
    LocalExecutionEnvironment,
    ProviderProfile,
    SessionConfig,
    Tool,
    ToolCall,
    ToolRegistry,
    ToolResult
  }

  alias AttractorEx.LLM.{Client, Message, Request, Response}

  @states [:idle, :processing, :awaiting_input, :closed]

  defstruct id: nil,
            provider_profile: nil,
            execution_env: nil,
            history: [],
            events: [],
            config: %SessionConfig{},
            state: :idle,
            llm_client: nil,
            steering_queue: :queue.new(),
            followup_queue: :queue.new(),
            subagents: %{},
            depth: 0,
            abort_signaled: false

  @type state :: :idle | :processing | :awaiting_input | :closed

  @type turn ::
          %{type: :user, content: String.t(), timestamp: DateTime.t()}
          | %{
              type: :assistant,
              content: String.t(),
              tool_calls: list(),
              reasoning: String.t() | nil,
              usage: map(),
              response_id: String.t() | nil,
              timestamp: DateTime.t()
            }
          | %{type: :tool_results, results: [ToolResult.t()], timestamp: DateTime.t()}
          | %{type: :steering, content: String.t(), timestamp: DateTime.t()}
          | %{type: :system, content: String.t(), timestamp: DateTime.t()}

  @type t :: %__MODULE__{
          id: String.t(),
          provider_profile: ProviderProfile.t(),
          execution_env: term(),
          history: [turn()],
          events: [Event.t()],
          config: SessionConfig.t(),
          state: state(),
          llm_client: Client.t(),
          steering_queue: :queue.queue(String.t()),
          followup_queue: :queue.queue(String.t()),
          subagents: map(),
          depth: non_neg_integer(),
          abort_signaled: boolean()
        }

  @spec new(Client.t(), ProviderProfile.t(), keyword()) :: t()
  @doc "Builds a new coding-agent session."
  def new(%Client{} = llm_client, %ProviderProfile{} = profile, opts \\ []) do
    config_opts = Keyword.get(opts, :config, [])

    %__MODULE__{
      id: Integer.to_string(System.unique_integer([:positive])),
      provider_profile: profile,
      execution_env: Keyword.get(opts, :execution_env, LocalExecutionEnvironment.new()),
      config: SessionConfig.new(config_opts),
      llm_client: llm_client
    }
  end

  @spec steer(t(), String.t()) :: t()
  @doc "Queues steering text to be injected on the next round."
  def steer(%__MODULE__{} = session, message) when is_binary(message) do
    %{session | steering_queue: :queue.in(message, session.steering_queue)}
  end

  @spec follow_up(t(), String.t()) :: t()
  @doc "Queues a follow-up user input to run after the current submission completes."
  def follow_up(%__MODULE__{} = session, message) when is_binary(message) do
    %{session | followup_queue: :queue.in(message, session.followup_queue)}
  end

  @spec abort(t()) :: t()
  @doc "Marks the session as aborted and closed."
  def abort(%__MODULE__{} = session) do
    %{session | abort_signaled: true, state: :closed}
  end

  @spec close(t()) :: t()
  @doc "Closes the session without aborting an in-flight tool."
  def close(%__MODULE__{} = session) do
    %{session | state: :closed}
  end

  @spec run_subagent_tool(t(), String.t(), map()) ::
          {String.t() | map() | list() | term(), t()} | no_return()
  @doc """
  Executes a session-managed subagent tool and returns `{output, updated_session}`.
  """
  def run_subagent_tool(%__MODULE__{} = session, tool_name, args)
      when tool_name in ["spawn_agent", "send_input", "wait", "close_agent"] and is_map(args) do
    case tool_name do
      "spawn_agent" -> spawn_subagent(session, args)
      "send_input" -> send_subagent_input(session, args)
      "wait" -> wait_on_subagent(session, args)
      "close_agent" -> close_subagent(session, args)
    end
  end

  @spec submit(t(), String.t()) :: t()
  @doc "Submits a user message into the agent loop."
  def submit(%__MODULE__{state: :closed} = session, _input), do: session

  def submit(%__MODULE__{} = session, user_input) when is_binary(user_input) do
    completed =
      session
      |> set_state(:processing)
      |> emit(:session_start, %{input: user_input})
      |> append_turn(%{type: :user, content: user_input, timestamp: DateTime.utc_now()})
      |> emit(:user_input, %{content: user_input})
      |> drain_steering()
      |> run_rounds(0)
      |> process_followups()

    finalized = maybe_set_idle(completed)
    emit(finalized, :session_end, %{final_state: finalized.state})
  end

  defp process_followups(%__MODULE__{state: :closed} = session), do: session

  defp process_followups(%__MODULE__{} = session) do
    case :queue.out(session.followup_queue) do
      {{:value, next_input}, rest} ->
        updated = %{session | followup_queue: rest}
        submit(updated, next_input)

      {:empty, _rest} ->
        session
    end
  end

  defp run_rounds(%__MODULE__{} = session, round_count) do
    cond do
      session.abort_signaled ->
        session

      turn_limit_reached?(session.config.max_turns, count_turns(session)) ->
        emit(session, :turn_limit, %{total_turns: count_turns(session)})

      true ->
        request = build_request(session)
        session = maybe_emit_context_warning(session, request)

        case Client.complete(session.llm_client, request) do
          {:error, reason} ->
            session
            |> emit(:error, %{source: :llm, error: inspect(reason)})
            |> append_turn(%{
              type: :system,
              content: "LLM error: #{inspect(reason)}",
              timestamp: DateTime.utc_now()
            })
            |> set_state(:closed)

          %Response{} = response ->
            after_assistant = append_assistant_turn(session, response)
            normalized_tool_calls = normalize_tool_calls(response.tool_calls)

            if normalized_tool_calls == [] do
              after_assistant
            else
              if turn_limit_reached?(session.config.max_tool_rounds_per_input, round_count) do
                emit(after_assistant, :turn_limit, %{round: round_count})
              else
                after_assistant
                |> execute_tool_round(normalized_tool_calls, round_count + 1)
              end
            end
        end
    end
  end

  defp append_assistant_turn(%__MODULE__{} = session, %Response{} = response) do
    text = response.text || ""

    session
    |> maybe_emit_assistant_text_start(text, response)
    |> append_turn(%{
      type: :assistant,
      content: text,
      tool_calls: normalize_tool_calls(response.tool_calls),
      reasoning: response.reasoning,
      usage: response.usage || %{},
      response_id: response.id,
      timestamp: DateTime.utc_now()
    })
    |> maybe_emit_assistant_text_delta(text, response)
    |> emit(:assistant_text_end, %{
      text: text,
      reasoning: response.reasoning,
      response_id: response.id
    })
  end

  defp execute_tool_round(%__MODULE__{} = session, tool_calls, round_count) do
    {results, events, updated_session} =
      execute_tool_calls(session, normalize_tool_calls(tool_calls))

    next_session =
      updated_session
      |> append_events(events)
      |> append_turn(%{type: :tool_results, results: results, timestamp: DateTime.utc_now()})
      |> drain_steering()

    case maybe_emit_loop_detection(next_session) do
      {loop_session, true} -> loop_session
      {loop_session, false} -> run_rounds(loop_session, round_count)
    end
  end

  defp build_request(%__MODULE__{} = session) do
    working_dir = execution_working_directory(session.execution_env)
    platform = execution_platform(session.execution_env)
    profile = session.provider_profile
    project_docs = load_project_docs(working_dir, profile.id)
    environment_context = execution_environment_context(session.execution_env)

    system_prompt =
      ProviderProfile.build_system_prompt(profile,
        environment: session.execution_env,
        working_dir: working_dir,
        platform: platform,
        project_docs: project_docs,
        tool_names: Enum.map(profile.tools, & &1.name),
        environment_context: environment_context,
        date: Date.utc_today() |> Date.to_iso8601()
      )

    %Request{
      model: profile.model,
      provider: profile.id,
      messages: [%Message{role: :system, content: system_prompt}] ++ history_to_messages(session),
      tools: ProviderProfile.tool_definitions(profile),
      tool_choice: "auto",
      reasoning_effort: session.config.reasoning_effort || "high",
      provider_options: profile.provider_options,
      metadata: %{
        "session_id" => session.id,
        "session_depth" => session.depth,
        "working_directory" => working_dir,
        "platform" => platform,
        "project_docs" => Enum.map(project_docs, & &1.path),
        "active_subagent_ids" => session.subagents |> Map.keys() |> Enum.sort()
      }
    }
  end

  defp history_to_messages(%__MODULE__{} = session) do
    Enum.flat_map(session.history, fn
      %{type: :user, content: content} ->
        [%Message{role: :user, content: content}]

      %{type: :assistant, content: content} ->
        [%Message{role: :assistant, content: content}]

      %{type: :system, content: content} ->
        [%Message{role: :system, content: content}]

      %{type: :steering, content: content} ->
        [%Message{role: :user, content: content}]

      %{type: :tool_results, results: results} ->
        [%Message{role: :tool, content: encode_tool_results(results)}]

      _ ->
        []
    end)
  end

  defp encode_tool_results(results) do
    Enum.map_join(results, "\n", fn result ->
      status = if result.is_error, do: "error", else: "ok"
      "#{result.tool_call_id || "call"}|#{status}|#{result.content}"
    end)
  end

  defp execute_tool_calls(%__MODULE__{} = session, tool_calls) do
    profile = session.provider_profile
    registry = profile.tool_registry

    all_environment_tools? =
      Enum.all?(tool_calls, fn tool_call ->
        case ToolRegistry.get(registry, tool_call.name) do
          %Tool{target: :session} -> false
          %Tool{} -> true
          nil -> true
        end
      end)

    if profile.supports_parallel_tool_calls and length(tool_calls) > 1 and all_environment_tools? do
      stream_results =
        tool_calls
        |> Task.async_stream(&execute_single_tool(session, &1),
          timeout: session.config.max_command_timeout_ms + 100,
          on_timeout: :kill_task,
          ordered: true
        )
        |> Enum.to_list()

      task_results =
        Enum.zip(tool_calls, stream_results)
        |> Enum.map(fn
          {_tool_call, {:ok, value}} ->
            value

          {tool_call, {:exit, reason}} ->
            error_msg = "Tool error (#{tool_call.name}): #{format_task_exit(reason)}"

            end_event =
              build_event(:tool_call_end, session.id, %{call_id: tool_call.id, error: error_msg})

            error_event =
              build_event(:error, session.id, %{
                source: :tool,
                tool_name: tool_call.name,
                call_id: tool_call.id,
                error: error_msg
              })

            {
              %ToolResult{tool_call_id: tool_call.id, content: error_msg, is_error: true},
              [
                build_event(:tool_call_start, session.id, %{
                  tool_name: tool_call.name,
                  call_id: tool_call.id
                }),
                error_event,
                end_event
              ],
              session
            }
        end)

      {
        Enum.map(task_results, fn {result, _events, _updated_session} -> result end),
        Enum.flat_map(task_results, fn {_result, events, _updated_session} -> events end),
        session
      }
    else
      Enum.reduce(tool_calls, {[], [], session}, fn tool_call,
                                                    {results, events, current_session} ->
        {result, new_events, updated_session} = execute_single_tool(current_session, tool_call)
        {results ++ [result], events ++ new_events, updated_session}
      end)
    end
  end

  defp execute_single_tool(%__MODULE__{} = session, %ToolCall{} = tool_call) do
    start_event =
      build_event(:tool_call_start, session.id, %{
        tool_name: tool_call.name,
        call_id: tool_call.id
      })

    case ToolRegistry.get(session.provider_profile.tool_registry, tool_call.name) do
      nil ->
        error_msg = "Unknown tool: #{tool_call.name}"

        end_event =
          build_event(:tool_call_end, session.id, %{call_id: tool_call.id, error: error_msg})

        error_event =
          build_event(:error, session.id, %{
            source: :tool,
            tool_name: tool_call.name,
            call_id: tool_call.id,
            error: error_msg
          })

        {
          %ToolResult{tool_call_id: tool_call.id, content: error_msg, is_error: true},
          [start_event, error_event, end_event],
          session
        }

      tool ->
        args = normalize_arguments(tool_call.arguments)

        case validate_tool_arguments(tool, args) do
          :ok ->
            timeout_ms = resolve_tool_timeout_ms(tool_call.name, args, session.config)

            case run_tool_with_timeout(
                   fn -> execute_tool_target(tool, args, session) end,
                   timeout_ms
                 ) do
              {:ok, {raw_output, updated_session}} ->
                raw_text = normalize_tool_output(raw_output)
                truncated_output = truncate_tool_output(raw_text, tool_call.name, session.config)

                delta_event =
                  build_event(:tool_call_output_delta, session.id, %{
                    call_id: tool_call.id,
                    tool_name: tool_call.name,
                    output: raw_text
                  })

                end_event =
                  build_event(:tool_call_end, session.id, %{
                    call_id: tool_call.id,
                    tool_name: tool_call.name,
                    output: raw_text
                  })

                {
                  %ToolResult{
                    tool_call_id: tool_call.id,
                    content: truncated_output,
                    is_error: false
                  },
                  [start_event, delta_event, end_event],
                  updated_session
                }

              {:error, :timeout} ->
                error_msg = "Tool error (#{tool_call.name}): timeout after #{timeout_ms}ms"

                end_event =
                  build_event(:tool_call_end, session.id, %{
                    call_id: tool_call.id,
                    error: error_msg
                  })

                error_event =
                  build_event(:error, session.id, %{
                    source: :tool,
                    tool_name: tool_call.name,
                    call_id: tool_call.id,
                    error: error_msg
                  })

                {%ToolResult{tool_call_id: tool_call.id, content: error_msg, is_error: true},
                 [start_event, error_event, end_event], session}

              {:error, reason} ->
                error_msg = "Tool error (#{tool_call.name}): #{reason}"

                end_event =
                  build_event(:tool_call_end, session.id, %{
                    call_id: tool_call.id,
                    error: error_msg
                  })

                error_event =
                  build_event(:error, session.id, %{
                    source: :tool,
                    tool_name: tool_call.name,
                    call_id: tool_call.id,
                    error: error_msg
                  })

                {%ToolResult{tool_call_id: tool_call.id, content: error_msg, is_error: true},
                 [start_event, error_event, end_event], session}
            end

          {:error, reason} ->
            error_msg = "Tool error (#{tool_call.name}): #{reason}"

            end_event =
              build_event(:tool_call_end, session.id, %{call_id: tool_call.id, error: error_msg})

            error_event =
              build_event(:error, session.id, %{
                source: :tool,
                tool_name: tool_call.name,
                call_id: tool_call.id,
                error: error_msg
              })

            {%ToolResult{tool_call_id: tool_call.id, content: error_msg, is_error: true},
             [start_event, error_event, end_event], session}
        end
    end
  end

  defp execute_tool_target(%Tool{target: :session} = tool, args, %__MODULE__{} = session) do
    case tool.execute.(args, session) do
      {output, %__MODULE__{} = updated_session} -> {output, updated_session}
      output -> {output, session}
    end
  end

  defp execute_tool_target(%Tool{} = tool, args, %__MODULE__{} = session) do
    {tool.execute.(args, session.execution_env), session}
  end

  defp normalize_arguments(arguments) when is_map(arguments), do: arguments

  defp normalize_arguments(arguments) when is_binary(arguments) do
    case Jason.decode(arguments) do
      {:ok, value} when is_map(value) -> value
      _ -> %{}
    end
  end

  defp normalize_arguments(_arguments), do: %{}

  defp normalize_tool_output(value) when is_binary(value), do: value

  defp normalize_tool_output(value) do
    inspect(value, pretty: true, limit: :infinity)
  end

  defp truncate_tool_output(text, tool_name, config) do
    char_limit =
      Map.get(config.tool_output_limits, tool_name, config.tool_output_limits["__default__"])

    char_limited =
      truncate_by_chars(
        text,
        char_limit
      )

    line_limit = Map.get(config.tool_output_line_limits, tool_name)

    final_text =
      if is_integer(line_limit) do
        truncate_by_lines(char_limited, line_limit)
      else
        char_limited
      end

    hard_cap_chars(final_text, char_limit)
  end

  defp truncate_by_chars(text, limit) when is_integer(limit) and limit > 0 do
    if String.length(text) <= limit do
      text
    else
      removed = String.length(text) - limit
      marker_full = "\n[WARNING: Tool output was truncated. #{removed} characters removed...]\n"
      marker = bounded_marker(marker_full, limit)
      remaining_budget = max(limit - String.length(marker), 0)
      head_size = div(remaining_budget, 2)
      tail_size = remaining_budget - head_size
      head = String.slice(text, 0, head_size)
      tail = if tail_size > 0, do: String.slice(text, -tail_size, tail_size), else: ""
      String.slice(head <> marker <> tail, 0, limit)
    end
  end

  defp truncate_by_chars(text, _limit), do: text

  defp truncate_by_lines(text, limit) when is_integer(limit) and limit > 0 do
    lines = String.split(text, "\n")

    if length(lines) <= limit do
      text
    else
      removed = length(lines) - limit
      head_size = div(limit, 2)
      tail_size = limit - head_size
      head = lines |> Enum.take(head_size) |> Enum.join("\n")
      tail = lines |> Enum.take(-tail_size) |> Enum.join("\n")
      marker = "\n[WARNING: Tool output was truncated. #{removed} lines removed...]\n"
      head <> marker <> tail
    end
  end

  defp truncate_by_lines(text, _limit), do: text

  defp maybe_emit_loop_detection(%__MODULE__{} = session) do
    if session.config.enable_loop_detection and
         detect_loop(session.history, session.config.loop_detection_window) do
      warning =
        "Loop detected: the last #{session.config.loop_detection_window} tool calls follow a repeating pattern. Try a different approach."

      detected_session =
        session
        |> append_turn(%{type: :steering, content: warning, timestamp: DateTime.utc_now()})
        |> emit(:loop_detection, %{message: warning})

      {detected_session, true}
    else
      {session, false}
    end
  end

  defp detect_loop(history, window) when is_integer(window) and window > 1 do
    round_signatures =
      history
      |> Enum.flat_map(fn
        %{type: :assistant, tool_calls: calls} ->
          if calls == [] do
            []
          else
            [round_signature(calls)]
          end

        _ ->
          []
      end)

    if length(round_signatures) < window do
      false
    else
      recent = Enum.take(round_signatures, -window)
      Enum.uniq(recent) |> length() == 1
    end
  end

  defp detect_loop(_history, _window), do: false

  defp tool_signature(%ToolCall{name: name, arguments: arguments}) do
    "#{name}:#{normalize_tool_output(arguments)}"
  end

  defp round_signature(calls) do
    Enum.map_join(calls, "||", &tool_signature/1)
  end

  defp normalize_tool_calls(tool_calls) when is_list(tool_calls) do
    tool_calls
    |> Enum.map(&normalize_tool_call/1)
    |> Enum.reject(&is_nil/1)
  end

  defp normalize_tool_calls(_), do: []

  defp normalize_tool_call(%ToolCall{} = tool_call), do: tool_call

  defp normalize_tool_call(%{name: name} = call) do
    normalized_name = name |> to_string() |> String.trim()

    if normalized_name == "" do
      nil
    else
      %ToolCall{
        id: Map.get(call, :id) || Map.get(call, "id"),
        name: normalized_name,
        arguments: Map.get(call, :arguments) || Map.get(call, "arguments") || %{}
      }
    end
  end

  defp normalize_tool_call(%{"name" => name} = call) do
    normalized_name = name |> to_string() |> String.trim()

    if normalized_name == "" do
      nil
    else
      %ToolCall{
        id: Map.get(call, "id") || Map.get(call, :id),
        name: normalized_name,
        arguments: Map.get(call, "arguments") || Map.get(call, :arguments) || %{}
      }
    end
  end

  defp normalize_tool_call(_call), do: nil

  defp bounded_marker(marker, limit) do
    if String.length(marker) <= limit do
      marker
    else
      String.slice(marker, 0, limit)
    end
  end

  defp hard_cap_chars(text, limit) when is_integer(limit) and limit > 0 do
    if String.length(text) <= limit do
      text
    else
      String.slice(text, 0, limit)
    end
  end

  defp hard_cap_chars(text, _limit), do: text

  defp resolve_tool_timeout_ms(tool_name, args, config) do
    override =
      if tool_name in ["shell", "shell_command"] do
        parse_timeout_ms(Map.get(args, "timeout_ms") || Map.get(args, :timeout_ms))
      else
        nil
      end

    timeout_ms = override || config.default_command_timeout_ms
    timeout_ms |> max(1) |> min(config.max_command_timeout_ms)
  end

  defp parse_timeout_ms(value) when is_integer(value) and value > 0, do: value

  defp parse_timeout_ms(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {parsed, ""} when parsed > 0 -> parsed
      _ -> nil
    end
  end

  defp parse_timeout_ms(_value), do: nil

  defp run_tool_with_timeout(callback, timeout_ms) when is_function(callback, 0) do
    parent = self()
    ref = make_ref()

    {pid, monitor_ref} =
      spawn_monitor(fn ->
        result =
          try do
            {:ok, callback.()}
          rescue
            error -> {:error, Exception.message(error)}
          catch
            kind, reason -> {:error, format_caught_failure(kind, reason)}
          end

        send(parent, {ref, result})
      end)

    receive do
      {^ref, {:ok, value}} ->
        flush_monitor(monitor_ref)
        {:ok, value}

      {^ref, {:error, reason}} ->
        flush_monitor(monitor_ref)
        {:error, reason}

      {:DOWN, ^monitor_ref, :process, ^pid, reason} ->
        {:error, format_task_exit(reason)}
    after
      timeout_ms ->
        _ = Process.exit(pid, :kill)
        consume_late_worker_reply(ref, monitor_ref, pid)
    end
  end

  defp format_task_exit(reason) do
    case reason do
      {exception, _stacktrace} when is_struct(exception, Exception) ->
        Exception.message(exception)

      _ ->
        inspect(reason)
    end
  end

  defp format_caught_failure(kind, reason) do
    "#{kind}: #{inspect(reason)}"
  end

  defp consume_late_worker_reply(ref, monitor_ref, pid) do
    receive do
      {^ref, _result} ->
        flush_monitor(monitor_ref)
        {:error, :timeout}

      {:DOWN, ^monitor_ref, :process, ^pid, _reason} ->
        drain_result_message(ref)
        {:error, :timeout}
    after
      20 ->
        drain_result_message(ref)
        flush_monitor(monitor_ref)
        {:error, :timeout}
    end
  end

  defp flush_monitor(monitor_ref), do: Process.demonitor(monitor_ref, [:flush])

  defp drain_result_message(ref) do
    receive do
      {^ref, _result} -> :ok
    after
      0 -> :ok
    end
  end

  defp discover_project_docs(working_dir, provider_id) do
    common_docs = find_docs_in_ancestors(working_dir, "AGENTS.md")

    provider_docs =
      case provider_id do
        "anthropic" -> find_docs_in_ancestors(working_dir, "CLAUDE.md")
        "gemini" -> find_docs_in_ancestors(working_dir, "GEMINI.md")
        "openai" -> find_docs_in_ancestors(working_dir, "CODEX.md")
        _ -> []
      end

    codex_instruction_docs =
      find_docs_in_ancestors(working_dir, Path.join(".codex", "instructions.md"))

    common_docs ++ provider_docs ++ codex_instruction_docs
  end

  defp load_project_docs(working_dir, provider_id) do
    working_dir
    |> discover_project_docs(provider_id)
    |> Enum.uniq()
    |> load_project_doc_contents()
  end

  defp load_project_doc_contents(paths) do
    marker = "[Project instructions truncated at 32KB]"

    {docs, _remaining, _truncated?} =
      Enum.reduce_while(paths, {[], 32_000, false}, fn path, {docs, remaining, _truncated?} ->
        case File.read(path) do
          {:ok, content} ->
            content_bytes = byte_size(content)

            cond do
              remaining <= 0 ->
                {:halt, {docs, 0, true}}

              content_bytes <= remaining ->
                {:cont,
                 {docs ++ [%{path: path, content: content}], remaining - content_bytes, false}}

              true ->
                allowed = max(remaining - byte_size(marker), 0)
                truncated_content = :binary.part(content, 0, allowed) <> marker
                {:halt, {docs ++ [%{path: path, content: truncated_content}], 0, true}}
            end

          {:error, _reason} ->
            {:cont, {docs, remaining, false}}
        end
      end)

    docs
  end

  defp find_docs_in_ancestors(dir, filename) do
    dir
    |> Path.expand()
    |> ancestor_paths()
    |> Enum.reverse()
    |> Enum.filter(fn current_dir ->
      File.exists?(Path.join(current_dir, filename))
    end)
    |> Enum.map(&Path.join(&1, filename))
  end

  defp ancestor_paths(dir) do
    Stream.unfold(dir, fn
      nil ->
        nil

      current ->
        parent = Path.dirname(current)

        next =
          cond do
            parent == current -> nil
            true -> parent
          end

        {current, next}
    end)
    |> Enum.to_list()
  end

  defp drain_steering(%__MODULE__{} = session) do
    case :queue.out(session.steering_queue) do
      {{:value, msg}, rest} ->
        session
        |> Map.put(:steering_queue, rest)
        |> append_turn(%{type: :steering, content: msg, timestamp: DateTime.utc_now()})
        |> emit(:steering_injected, %{content: msg})
        |> drain_steering()

      {:empty, _rest} ->
        session
    end
  end

  defp append_turn(%__MODULE__{} = session, turn) do
    %{session | history: session.history ++ [turn]}
  end

  defp append_events(%__MODULE__{} = session, events) do
    %{session | events: session.events ++ events}
  end

  defp emit(%__MODULE__{} = session, kind, payload) do
    event = build_event(kind, session.id, payload)
    %{session | events: session.events ++ [event]}
  end

  defp build_event(kind, session_id, payload) do
    Event.new(kind, session_id, payload)
  end

  defp maybe_emit_assistant_text_start(%__MODULE__{} = session, "", _response), do: session

  defp maybe_emit_assistant_text_start(%__MODULE__{} = session, text, %Response{} = response) do
    emit(session, :assistant_text_start, %{text: text, response_id: response.id})
  end

  defp maybe_emit_assistant_text_delta(%__MODULE__{} = session, "", _response), do: session

  defp maybe_emit_assistant_text_delta(%__MODULE__{} = session, text, %Response{} = response) do
    emit(session, :assistant_text_delta, %{delta: text, text: text, response_id: response.id})
  end

  defp execution_working_directory(env) do
    if ExecutionEnvironment.implementation?(env) do
      ExecutionEnvironment.working_directory(env)
    else
      File.cwd!()
    end
  end

  defp execution_platform(env) do
    if ExecutionEnvironment.implementation?(env) do
      ExecutionEnvironment.platform(env)
    else
      "unknown"
    end
  end

  defp execution_environment_context(env) do
    if ExecutionEnvironment.implementation?(env) do
      ExecutionEnvironment.environment_context(env)
    else
      %{}
    end
  end

  defp maybe_emit_context_warning(%__MODULE__{} = session, %Request{} = request) do
    context_window = session.provider_profile.context_window_size

    if is_integer(context_window) and context_window > 0 do
      estimated_chars =
        request.messages
        |> Enum.map(&Message.content_text(&1.content))
        |> Enum.map(&String.length/1)
        |> Enum.sum()

      if estimated_chars >= trunc(context_window * 0.75) do
        emit(session, :context_warning, %{
          estimated_chars: estimated_chars,
          context_window_size: context_window
        })
      else
        session
      end
    else
      session
    end
  end

  defp validate_tool_arguments(%{parameters: %{"type" => "object"} = schema}, args)
       when is_map(args) do
    required = Map.get(schema, "required", [])
    properties = Map.get(schema, "properties", %{})

    case validate_required_arguments(required, args) do
      :ok -> validate_argument_types(args, properties)
      error -> error
    end
  end

  defp validate_tool_arguments(_tool, _args), do: :ok

  defp validate_required_arguments(required, args) do
    case Enum.find(required, fn key -> blank_argument?(Map.get(args, key)) end) do
      nil -> :ok
      key -> {:error, "invalid arguments: missing required field #{key}"}
    end
  end

  defp validate_argument_types(args, properties) do
    case Enum.find(args, fn {key, value} ->
           schema = Map.get(properties, key, %{})
           not valid_argument_type?(value, Map.get(schema, "type"))
         end) do
      nil -> :ok
      {key, _value} -> {:error, "invalid arguments: #{key} has wrong type"}
    end
  end

  defp blank_argument?(value), do: value in [nil, ""]

  defp valid_argument_type?(_value, nil), do: true
  defp valid_argument_type?(value, "string"), do: is_binary(value)
  defp valid_argument_type?(value, "integer"), do: is_integer(value)
  defp valid_argument_type?(value, "number"), do: is_integer(value) or is_float(value)
  defp valid_argument_type?(value, "boolean"), do: is_boolean(value)
  defp valid_argument_type?(value, "object"), do: is_map(value)
  defp valid_argument_type?(value, "array"), do: is_list(value)
  defp valid_argument_type?(_value, _type), do: true

  defp spawn_subagent(%__MODULE__{} = session, %{"task" => task} = args) do
    ensure_subagent_depth!(session)

    child_profile = build_subagent_profile(session.provider_profile, Map.get(args, "model"))
    child_env = build_subagent_environment(session.execution_env, Map.get(args, "working_dir"))
    child_config = build_subagent_config(session.config, Map.get(args, "max_turns"))

    child_session =
      new(session.llm_client, child_profile,
        execution_env: child_env,
        config: Map.from_struct(child_config) |> Enum.to_list()
      )
      |> Map.put(:depth, session.depth + 1)
      |> submit(task)

    status = classify_subagent_status(child_session)
    handle = %{id: child_session.id, session: child_session, status: status}

    updated_session =
      session
      |> put_in([Access.key(:subagents), child_session.id], handle)
      |> emit(:subagent_spawned, %{agent_id: child_session.id, status: status, task: task})

    {Jason.encode!(%{agent_id: child_session.id, status: status}), updated_session}
  end

  defp send_subagent_input(%__MODULE__{} = session, %{
         "agent_id" => agent_id,
         "message" => message
       }) do
    handle = fetch_subagent!(session, agent_id)
    ensure_subagent_open!(handle, agent_id)

    child_session = submit(handle.session, message)
    status = classify_subagent_status(child_session)
    updated_handle = %{handle | session: child_session, status: status}

    updated_session =
      session
      |> put_in([Access.key(:subagents), agent_id], updated_handle)
      |> emit(:subagent_input_sent, %{agent_id: agent_id, status: status})

    {Jason.encode!(%{agent_id: agent_id, status: status, accepted: true}), updated_session}
  end

  defp wait_on_subagent(%__MODULE__{} = session, %{"agent_id" => agent_id}) do
    handle = fetch_subagent!(session, agent_id)
    result = subagent_result(handle)

    updated_session =
      emit(session, :subagent_wait_completed, %{
        agent_id: agent_id,
        status: handle.status,
        success: result.success
      })

    {Jason.encode!(result), updated_session}
  end

  defp close_subagent(%__MODULE__{} = session, %{"agent_id" => agent_id}) do
    handle = fetch_subagent!(session, agent_id)
    final_session = close(handle.session)
    final_status = classify_subagent_status(final_session, handle.status)

    updated_session =
      session
      |> emit(:subagent_closed, %{agent_id: agent_id, status: final_status})
      |> update_in([Access.key(:subagents)], &Map.delete(&1, agent_id))

    {Jason.encode!(%{agent_id: agent_id, status: final_status, closed: true}), updated_session}
  end

  defp ensure_subagent_depth!(%__MODULE__{} = session) do
    if session.depth >= session.config.max_subagent_depth do
      raise "subagent depth limit exceeded (max_subagent_depth=#{session.config.max_subagent_depth})"
    end
  end

  defp build_subagent_profile(%ProviderProfile{} = profile, nil), do: profile
  defp build_subagent_profile(%ProviderProfile{} = profile, model), do: %{profile | model: model}

  defp build_subagent_environment(%LocalExecutionEnvironment{} = env, nil), do: env

  defp build_subagent_environment(%LocalExecutionEnvironment{} = env, working_dir)
       when is_binary(working_dir) do
    root = LocalExecutionEnvironment.working_directory(env)

    resolved =
      if Path.type(working_dir) == :absolute do
        Path.expand(working_dir)
      else
        Path.expand(working_dir, root)
      end

    unless String.starts_with?(resolved, root) do
      raise "subagent working_dir must stay within the parent working directory"
    end

    %{env | working_dir: resolved}
  end

  defp build_subagent_environment(env, nil), do: env

  defp build_subagent_environment(_env, _working_dir) do
    raise "subagent working_dir override requires LocalExecutionEnvironment"
  end

  defp build_subagent_config(%SessionConfig{} = config, nil), do: config

  defp build_subagent_config(%SessionConfig{} = config, max_turns),
    do: %{config | max_turns: max_turns}

  defp classify_subagent_status(%__MODULE__{} = child_session, fallback \\ nil) do
    cond do
      has_llm_error?(child_session) -> "failed"
      has_tool_error?(child_session) -> "failed"
      child_session.state == :closed and fallback == "completed" -> "completed"
      child_session.state == :closed -> "failed"
      true -> "completed"
    end
  end

  defp subagent_result(%{id: agent_id, session: %__MODULE__{} = child_session, status: status}) do
    %{
      agent_id: agent_id,
      status: status,
      output: last_assistant_output(child_session),
      success: status == "completed",
      turns_used: count_turns(child_session)
    }
  end

  defp fetch_subagent!(%__MODULE__{} = session, agent_id) do
    case Map.get(session.subagents, agent_id) do
      nil -> raise "unknown subagent: #{agent_id}"
      handle -> handle
    end
  end

  defp ensure_subagent_open!(%{session: %__MODULE__{state: :closed}}, agent_id) do
    raise "subagent is closed: #{agent_id}"
  end

  defp ensure_subagent_open!(_handle, _agent_id), do: :ok

  defp has_llm_error?(%__MODULE__{} = session) do
    Enum.any?(session.history, fn
      %{type: :system, content: content} -> String.starts_with?(content, "LLM error:")
      _ -> false
    end)
  end

  defp has_tool_error?(%__MODULE__{} = session) do
    Enum.any?(session.history, fn
      %{type: :tool_results, results: results} -> Enum.any?(results, & &1.is_error)
      _ -> false
    end)
  end

  defp last_assistant_output(%__MODULE__{} = session) do
    session.history
    |> Enum.reverse()
    |> Enum.find_value("", fn
      %{type: :assistant, content: content} -> content || ""
      _ -> nil
    end)
  end

  defp maybe_set_idle(%__MODULE__{state: :closed} = session), do: session
  defp maybe_set_idle(%__MODULE__{} = session), do: set_state(session, :idle)

  defp set_state(%__MODULE__{} = session, state) when state in @states do
    %{session | state: state}
  end

  defp turn_limit_reached?(0, _count), do: false
  defp turn_limit_reached?(limit, count), do: count >= limit
  defp count_turns(%__MODULE__{} = session), do: length(session.history)
end
