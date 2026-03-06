defmodule AttractorEx.Agent.Session do
  @moduledoc false

  alias AttractorEx.Agent.{
    LocalExecutionEnvironment,
    ProviderProfile,
    SessionConfig,
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
          events: [map()],
          config: SessionConfig.t(),
          state: state(),
          llm_client: Client.t(),
          steering_queue: :queue.queue(String.t()),
          followup_queue: :queue.queue(String.t()),
          subagents: map(),
          abort_signaled: boolean()
        }

  @spec new(Client.t(), ProviderProfile.t(), keyword()) :: t()
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
  def steer(%__MODULE__{} = session, message) when is_binary(message) do
    %{session | steering_queue: :queue.in(message, session.steering_queue)}
  end

  @spec follow_up(t(), String.t()) :: t()
  def follow_up(%__MODULE__{} = session, message) when is_binary(message) do
    %{session | followup_queue: :queue.in(message, session.followup_queue)}
  end

  @spec abort(t()) :: t()
  def abort(%__MODULE__{} = session) do
    %{session | abort_signaled: true, state: :closed}
  end

  @spec close(t()) :: t()
  def close(%__MODULE__{} = session) do
    %{session | state: :closed}
  end

  @spec submit(t(), String.t()) :: t()
  def submit(%__MODULE__{state: :closed} = session, _input), do: session

  def submit(%__MODULE__{} = session, user_input) when is_binary(user_input) do
    completed =
      session
      |> set_state(:processing)
      |> append_turn(%{type: :user, content: user_input, timestamp: DateTime.utc_now()})
      |> emit(:user_input, %{content: user_input})
      |> drain_steering()
      |> run_rounds(0)
      |> process_followups()

    completed
    |> maybe_set_idle()
    |> emit(:session_end, %{})
  end

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

        case Client.complete(session.llm_client, request) do
          {:error, reason} ->
            session
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
    session
    |> append_turn(%{
      type: :assistant,
      content: response.text || "",
      tool_calls: normalize_tool_calls(response.tool_calls),
      reasoning: response.reasoning,
      usage: response.usage || %{},
      response_id: response.id,
      timestamp: DateTime.utc_now()
    })
    |> emit(:assistant_text_end, %{text: response.text || "", reasoning: response.reasoning})
  end

  defp execute_tool_round(%__MODULE__{} = session, tool_calls, round_count) do
    {results, events} = execute_tool_calls(session, normalize_tool_calls(tool_calls))

    next_session =
      session
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
    profile = session.provider_profile

    system_prompt =
      ProviderProfile.build_system_prompt(profile,
        environment: session.execution_env,
        working_dir: working_dir,
        project_docs: discover_project_docs(working_dir, profile.id),
        date: Date.utc_today() |> Date.to_iso8601()
      )

    %Request{
      model: profile.model,
      provider: profile.id,
      messages: [%Message{role: :system, content: system_prompt}] ++ history_to_messages(session),
      tools: ProviderProfile.tool_definitions(profile),
      tool_choice: "auto",
      reasoning_effort: session.config.reasoning_effort || "high",
      provider_options: profile.provider_options
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

    if profile.supports_parallel_tool_calls and length(tool_calls) > 1 do
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
            end_event = build_event(:tool_call_end, %{call_id: tool_call.id, error: error_msg})

            {
              %ToolResult{tool_call_id: tool_call.id, content: error_msg, is_error: true},
              [
                build_event(:tool_call_start, %{tool_name: tool_call.name, call_id: tool_call.id}),
                end_event
              ]
            }
        end)

      {
        Enum.map(task_results, fn {result, _events} -> result end),
        Enum.flat_map(task_results, fn {_result, events} -> events end)
      }
    else
      task_results = Enum.map(tool_calls, &execute_single_tool(session, &1))

      {
        Enum.map(task_results, fn {result, _events} -> result end),
        Enum.flat_map(task_results, fn {_result, events} -> events end)
      }
    end
  end

  defp execute_single_tool(%__MODULE__{} = session, %ToolCall{} = tool_call) do
    start_event =
      build_event(:tool_call_start, %{tool_name: tool_call.name, call_id: tool_call.id})

    case ToolRegistry.get(session.provider_profile.tool_registry, tool_call.name) do
      nil ->
        error_msg = "Unknown tool: #{tool_call.name}"
        end_event = build_event(:tool_call_end, %{call_id: tool_call.id, error: error_msg})

        {
          %ToolResult{tool_call_id: tool_call.id, content: error_msg, is_error: true},
          [start_event, end_event]
        }

      tool ->
        args = normalize_arguments(tool_call.arguments)
        timeout_ms = resolve_tool_timeout_ms(tool_call.name, args, session.config)

        case run_tool_with_timeout(
               fn -> tool.execute.(args, session.execution_env) end,
               timeout_ms
             ) do
          {:ok, raw_output} ->
            raw_text = normalize_tool_output(raw_output)
            truncated_output = truncate_tool_output(raw_text, tool_call.name, session.config)

            end_event =
              build_event(:tool_call_end, %{call_id: tool_call.id, output: truncated_output})

            {
              %ToolResult{
                tool_call_id: tool_call.id,
                content: truncated_output,
                is_error: false
              },
              [start_event, end_event]
            }

          {:error, :timeout} ->
            error_msg = "Tool error (#{tool_call.name}): timeout after #{timeout_ms}ms"
            end_event = build_event(:tool_call_end, %{call_id: tool_call.id, error: error_msg})

            {%ToolResult{tool_call_id: tool_call.id, content: error_msg, is_error: true},
             [start_event, end_event]}

          {:error, reason} ->
            error_msg = "Tool error (#{tool_call.name}): #{reason}"
            end_event = build_event(:tool_call_end, %{call_id: tool_call.id, error: error_msg})

            {%ToolResult{tool_call_id: tool_call.id, content: error_msg, is_error: true},
             [start_event, end_event]}
        end
    end
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
    signatures =
      history
      |> Enum.flat_map(fn
        %{type: :assistant, tool_calls: calls} ->
          Enum.map(calls, &tool_signature/1)

        _ ->
          []
      end)

    if length(signatures) < window do
      false
    else
      recent = Enum.take(signatures, -window)
      Enum.uniq(recent) |> length() == 1
    end
  end

  defp detect_loop(_history, _window), do: false

  defp tool_signature(%ToolCall{name: name, arguments: arguments}) do
    "#{name}:#{normalize_tool_output(arguments)}"
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
      if tool_name == "shell_command" do
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

    pid =
      spawn(fn ->
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
        {:ok, value}

      {^ref, {:error, reason}} ->
        {:error, reason}
    after
      timeout_ms ->
        _ = Process.exit(pid, :kill)
        {:error, :timeout}
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

  defp discover_project_docs(working_dir, provider_id) do
    common = find_doc(working_dir, "AGENTS.md")

    provider_doc =
      case provider_id do
        "anthropic" -> find_doc(working_dir, "CLAUDE.md")
        "gemini" -> find_doc(working_dir, "GEMINI.md")
        "openai" -> find_doc(working_dir, "CODEX.md")
        _ -> nil
      end

    [common, provider_doc]
    |> Enum.reject(&is_nil/1)
  end

  defp find_doc(dir, filename) do
    path = Path.join(dir, filename)
    if File.exists?(path), do: path, else: nil
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
    event = build_event(kind, payload)
    %{session | events: session.events ++ [event]}
  end

  defp build_event(kind, payload) do
    %{kind: kind, payload: payload, timestamp: DateTime.utc_now()}
  end

  defp execution_working_directory(%LocalExecutionEnvironment{} = env) do
    LocalExecutionEnvironment.working_directory(env)
  end

  defp execution_working_directory(_env) do
    File.cwd!()
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
