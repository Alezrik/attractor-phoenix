defmodule AttractorEx.Agent.SessionTest do
  use ExUnit.Case, async: true

  alias AttractorEx.Agent.{
    BuiltinTools,
    LocalExecutionEnvironment,
    ProviderProfile,
    Session,
    Tool
  }

  alias AttractorEx.LLM.Client

  test "natural completion when response has no tool calls" do
    session = build_session("no_tools", [echo_tool()])
    completed = Session.submit(session, "hello")

    assert completed.state == :idle
    assert Enum.any?(completed.events, &(&1.kind == :session_start))
    assert event_kinds(completed) |> Enum.member?(:assistant_text_end)
    assert last_assistant_text(completed) == "done"
  end

  test "runs tool round and then finishes" do
    session = build_session("single_tool", [echo_tool()])
    completed = Session.submit(session, "run tool")

    assert completed.state == :idle
    assert last_assistant_text(completed) == "tool-complete"
    assert Enum.any?(completed.events, &(&1.kind == :tool_call_start))
    assert Enum.any?(completed.events, &(&1.kind == :tool_call_end))
  end

  test "uses high reasoning effort by default" do
    completed = Session.submit(build_session("echo_reasoning_effort", [echo_tool()]), "hello")
    assert last_assistant_text(completed) == "effort:high"
  end

  test "uses configured reasoning effort override" do
    completed =
      Session.submit(
        build_session("echo_reasoning_effort", [echo_tool()],
          config: [reasoning_effort: "medium"]
        ),
        "hello"
      )

    assert last_assistant_text(completed) == "effort:medium"
  end

  test "handles string-keyed tool call maps from provider payloads" do
    session = build_session("single_tool_string_keys", [echo_tool()])
    completed = Session.submit(session, "run tool")

    assert completed.state == :idle
    assert last_assistant_text(completed) == "tool-complete"
    tool_turn = Enum.find(completed.history, &(&1.type == :tool_results))
    [result] = tool_turn.results
    refute result.is_error
  end

  test "handles atom-keyed tool call maps" do
    session = build_session("single_tool_atom_keys", [echo_tool()])
    completed = Session.submit(session, "run tool")

    assert completed.state == :idle
    assert last_assistant_text(completed) == "tool-complete"
  end

  test "parses JSON string arguments for tool calls" do
    session = build_session("single_tool_json_args", [echo_tool()])
    completed = Session.submit(session, "run tool")
    tool_turn = Enum.find(completed.history, &(&1.type == :tool_results))
    [result] = tool_turn.results

    assert result.content == "hello"
  end

  test "falls back to empty map when tool arguments are invalid JSON" do
    session = build_session("single_tool_invalid_json_args", [echo_tool()])
    completed = Session.submit(session, "run tool")
    tool_turn = Enum.find(completed.history, &(&1.type == :tool_results))
    [result] = tool_turn.results

    assert result.content == ""
  end

  test "falls back to empty map when tool arguments are non-map non-binary" do
    session = build_session("single_tool_numeric_args", [echo_tool()])
    completed = Session.submit(session, "run tool")
    tool_turn = Enum.find(completed.history, &(&1.type == :tool_results))
    [result] = tool_turn.results

    assert result.content == ""
  end

  test "unknown tool returns error result and model can recover" do
    session = build_session("unknown_tool", [echo_tool()])
    completed = Session.submit(session, "unknown")

    tool_turn = Enum.find(completed.history, &(&1.type == :tool_results))
    [result] = tool_turn.results

    assert result.is_error
    assert result.content =~ "Unknown tool"
    assert last_assistant_text(completed) == "recovered-after-unknown"
  end

  test "steering message is injected before processing" do
    session =
      build_session("followup_echo", [echo_tool()])
      |> Session.steer("Use concise output")

    completed = Session.submit(session, "first prompt")
    steering = Enum.find(completed.history, &(&1.type == :steering))

    assert steering.content == "Use concise output"
    assert Enum.any?(completed.events, &(&1.kind == :steering_injected))
  end

  test "follow_up runs after current input completes" do
    session =
      build_session("followup_echo", [echo_tool()])
      |> Session.follow_up("second prompt")

    completed = Session.submit(session, "first prompt")

    user_turns = Enum.filter(completed.history, &(&1.type == :user))
    assert Enum.map(user_turns, & &1.content) == ["first prompt", "second prompt"]
  end

  test "returns unchanged session for submit when state is closed" do
    closed =
      build_session("no_tools", [echo_tool()])
      |> Session.close()

    result = Session.submit(closed, "ignored")
    assert result == closed
  end

  test "abort marks session as closed" do
    session = build_session("no_tools", [echo_tool()])
    aborted = Session.abort(session)

    assert aborted.state == :closed
    assert aborted.abort_signaled
  end

  test "abort_signaled short-circuits tool loop execution" do
    session =
      build_session("single_tool", [echo_tool()])
      |> Map.put(:abort_signaled, true)

    completed = Session.submit(session, "hello")

    assert completed.state == :idle
    refute Enum.any?(completed.history, &(&1.type == :assistant))
  end

  test "loop detection emits warning when identical tool call repeats" do
    session =
      build_session("looping_tool", [echo_tool()],
        config: [
          max_tool_rounds_per_input: 3,
          loop_detection_window: 3
        ]
      )

    completed = Session.submit(session, "loop")

    assert Enum.any?(completed.events, &(&1.kind == :loop_detection))

    assert Enum.any?(completed.history, fn turn ->
             turn.type == :steering and String.contains?(turn.content, "Loop detected")
           end)
  end

  test "loop detection terminates current processing cycle" do
    session =
      build_session("looping_tool", [echo_tool()],
        config: [
          max_tool_rounds_per_input: 0,
          loop_detection_window: 2
        ]
      )

    completed = Session.submit(session, "loop forever")
    assistant_turns = Enum.count(completed.history, &(&1.type == :assistant))

    assert assistant_turns == 2
    assert Enum.any?(completed.events, &(&1.kind == :loop_detection))
  end

  test "batched repeated tool calls in one round do not trigger loop detection" do
    session =
      build_session("batched_repeated_calls_once", [echo_tool()],
        config: [loop_detection_window: 2]
      )

    completed = Session.submit(session, "run batched")

    assert last_assistant_text(completed) == "batched-done"
    refute Enum.any?(completed.events, &(&1.kind == :loop_detection))
  end

  test "max turns emits limit event" do
    session = build_session("no_tools", [echo_tool()], config: [max_turns: 1])
    completed = Session.submit(session, "hello")

    assert Enum.any?(completed.events, fn event ->
             event.kind == :turn_limit and event.payload[:total_turns] == 1
           end)
  end

  test "max tool rounds emits limit event" do
    session = build_session("looping_tool", [echo_tool()], config: [max_tool_rounds_per_input: 1])
    completed = Session.submit(session, "hello")

    assert Enum.any?(completed.events, fn event ->
             event.kind == :turn_limit and event.payload[:round] == 1
           end)
  end

  test "max tool rounds still allows post-tool assistant completion" do
    session =
      build_session("single_tool", [echo_tool()], config: [max_tool_rounds_per_input: 1])

    completed = Session.submit(session, "hello")

    assert last_assistant_text(completed) == "tool-complete"

    refute Enum.any?(completed.events, fn event ->
             event.kind == :turn_limit
           end)
  end

  test "parallel tool calls execute concurrently when profile allows it" do
    session = build_session("parallel_tools", [slow_tool()], supports_parallel: true)

    {elapsed_us, completed} =
      :timer.tc(fn ->
        Session.submit(session, "parallel")
      end)

    assert elapsed_us < 520_000
    assert last_assistant_text(completed) == "parallel-done"
  end

  test "subagent tools spawn, continue, wait, and close child sessions" do
    session = build_session("subagent_roundtrip", BuiltinTools.for_provider(:default))
    completed = Session.submit(session, "delegate")

    assert last_assistant_text(completed) == "parent-subagent-complete"
    assert completed.subagents == %{}
    assert Enum.any?(completed.events, &(&1.kind == :subagent_spawned))
    assert Enum.any?(completed.events, &(&1.kind == :subagent_input_sent))
    assert Enum.any?(completed.events, &(&1.kind == :subagent_wait_completed))
    assert Enum.any?(completed.events, &(&1.kind == :subagent_closed))

    tool_turns = Enum.filter(completed.history, &(&1.type == :tool_results))
    wait_result = tool_turns |> Enum.at(2) |> Map.fetch!(:results) |> hd()
    decoded = Jason.decode!(wait_result.content)

    assert decoded["success"]
    assert decoded["output"] == "child:follow-up"
    assert decoded["turns_used"] > 0
  end

  test "subagents enforce configured maximum depth" do
    session = build_session("subagent_depth_limit", BuiltinTools.for_provider(:default))
    completed = Session.submit(session, "delegate")

    assert last_assistant_text(completed) == "parent-depth-limit-complete"

    tool_turns = Enum.filter(completed.history, &(&1.type == :tool_results))
    wait_result = tool_turns |> Enum.at(1) |> Map.fetch!(:results) |> hd() |> Map.fetch!(:content)
    decoded = Jason.decode!(wait_result)

    refute decoded["success"]
    assert decoded["output"] == "child-depth-limit-observed"
  end

  test "missing subagent errors are returned as tool failures and model can recover" do
    session = build_session("subagent_unknown_wait", BuiltinTools.for_provider(:default))
    completed = Session.submit(session, "missing")

    assert last_assistant_text(completed) == "recovered-after-missing-subagent"

    tool_turn = Enum.find(completed.history, &(&1.type == :tool_results))
    [result] = tool_turn.results

    assert result.is_error
    assert result.content =~ "unknown subagent"
  end

  test "tool output truncation applies character and line limits" do
    tool =
      %Tool{
        name: "shell_command",
        description: "test",
        parameters: %{},
        execute: fn _args, _env ->
          Enum.map_join(1..20, "\n", fn i -> "line-#{i}" end)
        end
      }

    session =
      build_session("single_shell_tool", [tool],
        config: [
          tool_output_limits: %{"shell_command" => 30, "__default__" => 30},
          tool_output_line_limits: %{"shell_command" => 4}
        ]
      )

    completed = Session.submit(session, "truncate")
    tool_turn = Enum.find(completed.history, &(&1.type == :tool_results))
    [result] = tool_turn.results

    assert result.content =~ "[WARNING: Tool output"
  end

  test "character truncation never exceeds configured limit" do
    tool =
      %Tool{
        name: "shell_command",
        description: "test",
        parameters: %{},
        execute: fn _args, _env -> String.duplicate("x", 500) end
      }

    session =
      build_session("single_shell_tool", [tool],
        config: [
          tool_output_limits: %{"shell_command" => 30, "__default__" => 30},
          tool_output_line_limits: %{}
        ]
      )

    completed = Session.submit(session, "truncate")
    tool_turn = Enum.find(completed.history, &(&1.type == :tool_results))
    [result] = tool_turn.results

    assert String.length(result.content) <= 30
    assert result.content =~ "[WARNING: Tool output"
  end

  test "line truncation fallback keeps original output when limit is not integer" do
    tool =
      %Tool{
        name: "shell_command",
        description: "test",
        parameters: %{},
        execute: fn _args, _env -> Enum.map_join(1..10, "\n", &"line-#{&1}") end
      }

    session =
      build_session("single_shell_tool", [tool],
        config: [
          tool_output_limits: %{"shell_command" => 500, "__default__" => 500},
          tool_output_line_limits: %{"shell_command" => nil}
        ]
      )

    completed = Session.submit(session, "truncate")
    tool_turn = Enum.find(completed.history, &(&1.type == :tool_results))
    [result] = tool_turn.results

    refute String.contains?(result.content, "lines removed")
  end

  test "line truncation still respects final character limit" do
    tool =
      %Tool{
        name: "shell_command",
        description: "test",
        parameters: %{},
        execute: fn _args, _env -> Enum.map_join(1..30, "\n", &"x#{&1}") end
      }

    session =
      build_session("single_shell_tool", [tool],
        config: [
          tool_output_limits: %{"shell_command" => 40, "__default__" => 40},
          tool_output_line_limits: %{"shell_command" => 4}
        ]
      )

    completed = Session.submit(session, "truncate")
    tool_turn = Enum.find(completed.history, &(&1.type == :tool_results))
    [result] = tool_turn.results

    assert String.length(result.content) <= 40
  end

  test "tool_call_end event output is bounded by truncation limit" do
    tool =
      %Tool{
        name: "shell_command",
        description: "test",
        parameters: %{},
        execute: fn _args, _env -> String.duplicate("x", 500) end
      }

    session =
      build_session("single_shell_tool", [tool],
        config: [
          tool_output_limits: %{"shell_command" => 60, "__default__" => 60},
          tool_output_line_limits: %{}
        ]
      )

    completed = Session.submit(session, "truncate")

    event =
      Enum.find(completed.events, fn item ->
        item.kind == :tool_call_end and is_binary(item.payload[:output])
      end)

    assert String.length(event.payload[:output]) <= 60
  end

  test "tool execution times out using default session timeout" do
    tool =
      %Tool{
        name: "shell_command",
        description: "slow shell",
        parameters: %{},
        execute: fn _args, _env ->
          Process.sleep(200)
          "done"
        end
      }

    session =
      build_session("single_shell_tool", [tool],
        config: [
          default_command_timeout_ms: 50,
          max_command_timeout_ms: 500
        ]
      )

    completed = Session.submit(session, "run")
    tool_turn = Enum.find(completed.history, &(&1.type == :tool_results))
    [result] = tool_turn.results

    assert result.is_error
    assert result.content =~ "timeout"
  end

  test "shell timeout_ms argument overrides default timeout within max cap" do
    tool =
      %Tool{
        name: "shell_command",
        description: "slow shell",
        parameters: %{},
        execute: fn _args, _env ->
          Process.sleep(150)
          "done"
        end
      }

    session =
      build_session("single_shell_tool_with_timeout_arg", [tool],
        config: [
          default_command_timeout_ms: 50,
          max_command_timeout_ms: 500
        ]
      )

    completed = Session.submit(session, "run")
    tool_turn = Enum.find(completed.history, &(&1.type == :tool_results))
    [result] = tool_turn.results

    refute result.is_error
    assert result.content == "done"
  end

  test "string shell timeout_ms argument is parsed when valid" do
    tool =
      %Tool{
        name: "shell_command",
        description: "slow shell",
        parameters: %{},
        execute: fn _args, _env ->
          Process.sleep(150)
          "done"
        end
      }

    session =
      build_session("single_shell_tool_with_timeout_string_arg", [tool],
        config: [
          default_command_timeout_ms: 50,
          max_command_timeout_ms: 500
        ]
      )

    completed = Session.submit(session, "run")
    tool_turn = Enum.find(completed.history, &(&1.type == :tool_results))
    [result] = tool_turn.results

    refute result.is_error
    assert result.content == "done"
  end

  test "invalid shell timeout argument falls back to default timeout" do
    tool =
      %Tool{
        name: "shell_command",
        description: "slow shell",
        parameters: %{},
        execute: fn _args, _env ->
          Process.sleep(80)
          "done"
        end
      }

    session =
      build_session("single_shell_tool_with_invalid_timeout_arg", [tool],
        config: [
          default_command_timeout_ms: 10,
          max_command_timeout_ms: 500
        ]
      )

    completed = Session.submit(session, "run")
    tool_turn = Enum.find(completed.history, &(&1.type == :tool_results))
    [result] = tool_turn.results

    assert result.is_error
    assert result.content =~ "timeout"
  end

  test "late tool reply after timeout is treated as timeout" do
    tool =
      %Tool{
        name: "shell_command",
        description: "slow shell",
        parameters: %{},
        execute: fn _args, _env ->
          Process.sleep(40)
          "done"
        end
      }

    session =
      build_session("single_shell_tool", [tool],
        config: [
          default_command_timeout_ms: 5,
          max_command_timeout_ms: 500
        ]
      )

    completed = Session.submit(session, "run")
    tool_turn = Enum.find(completed.history, &(&1.type == :tool_results))
    [result] = tool_turn.results

    assert result.is_error
    assert result.content =~ "timeout"
  end

  test "line truncation uses line-based marker when char budget allows it" do
    tool =
      %Tool{
        name: "shell_command",
        description: "test",
        parameters: %{},
        execute: fn _args, _env -> Enum.map_join(1..10, "\n", &"line-#{&1}") end
      }

    session =
      build_session("single_shell_tool", [tool],
        config: [
          tool_output_limits: %{"shell_command" => 500, "__default__" => 500},
          tool_output_line_limits: %{"shell_command" => 4}
        ]
      )

    completed = Session.submit(session, "truncate")
    tool_turn = Enum.find(completed.history, &(&1.type == :tool_results))
    [result] = tool_turn.results

    assert result.content =~ "lines removed"
    assert result.content =~ "line-1"
    assert result.content =~ "line-10"
  end

  test "tool output leaves content unchanged when no hard character limit is configured" do
    tool =
      %Tool{
        name: "echo",
        description: "plain output",
        parameters: %{},
        execute: fn _args, _env -> "hello" end
      }

    session =
      build_session("single_tool", [tool],
        config: [
          tool_output_limits: %{"echo" => nil, "__default__" => nil},
          tool_output_line_limits: %{}
        ]
      )

    completed = Session.submit(session, "run")
    tool_turn = Enum.find(completed.history, &(&1.type == :tool_results))
    [result] = tool_turn.results

    assert result.content == "hello"
  end

  test "loop detection is disabled when configured window is not greater than one" do
    session =
      build_session("looping_tool", [echo_tool()],
        config: [
          max_tool_rounds_per_input: 2,
          loop_detection_window: 1
        ]
      )

    completed = Session.submit(session, "loop")

    refute Enum.any?(completed.events, &(&1.kind == :loop_detection))
    assert Enum.any?(completed.events, &(&1.kind == :turn_limit))
  end

  test "repeated tool timeouts do not accumulate mailbox messages" do
    tool =
      %Tool{
        name: "shell_command",
        description: "slow shell",
        parameters: %{},
        execute: fn _args, _env ->
          Process.sleep(80)
          "done"
        end
      }

    baseline_len = Process.info(self(), :message_queue_len) |> elem(1)

    queue_lengths =
      for _ <- 1..5 do
        session =
          build_session("single_shell_tool", [tool],
            config: [
              default_command_timeout_ms: 10,
              max_command_timeout_ms: 500
            ]
          )

        _ = Session.submit(session, "run")
        Process.info(self(), :message_queue_len) |> elem(1)
      end

    assert Enum.all?(queue_lengths, &(&1 <= baseline_len))
  end

  test "repeated tool timeouts do not leave stale messages after final run" do
    tool =
      %Tool{
        name: "shell_command",
        description: "slow shell",
        parameters: %{},
        execute: fn _args, _env ->
          Process.sleep(80)
          "done"
        end
      }

    baseline_len = Process.info(self(), :message_queue_len) |> elem(1)

    for _ <- 1..5 do
      session =
        build_session("single_shell_tool", [tool],
          config: [
            default_command_timeout_ms: 10,
            max_command_timeout_ms: 500
          ]
        )

      _ = Session.submit(session, "run")
    end

    after_len = Process.info(self(), :message_queue_len) |> elem(1)
    assert after_len <= baseline_len
  end

  test "handles non-list tool_calls as natural completion" do
    session = build_session("invalid_tool_calls_shape", [echo_tool()])
    completed = Session.submit(session, "shape")

    assert last_assistant_text(completed) == "shape-done"
    refute Enum.any?(completed.events, &(&1.kind == :tool_call_start))
  end

  test "ignores malformed tool call list entries" do
    session = build_session("malformed_tool_call_list", [echo_tool()])
    completed = Session.submit(session, "shape")

    assert last_assistant_text(completed) == "shape-done"
    refute Enum.any?(completed.events, &(&1.kind == :tool_call_start))
    refute Enum.any?(completed.events, &(&1.kind == :turn_limit))
  end

  test "records tool errors when tool raises" do
    crashing_tool =
      %Tool{
        name: "echo",
        description: "crashes",
        parameters: %{},
        execute: fn _args, _env -> raise "boom" end
      }

    completed = Session.submit(build_session("single_tool", [crashing_tool]), "run")
    tool_turn = Enum.find(completed.history, &(&1.type == :tool_results))
    [result] = tool_turn.results

    assert result.is_error
    assert result.content =~ "Tool error"
  end

  test "records tool errors when tool throws" do
    throwing_tool =
      %Tool{
        name: "echo",
        description: "throws",
        parameters: %{},
        execute: fn _args, _env -> throw(:bad_state) end
      }

    completed = Session.submit(build_session("single_tool", [throwing_tool]), "run")
    tool_turn = Enum.find(completed.history, &(&1.type == :tool_results))
    [result] = tool_turn.results

    assert result.is_error
    assert result.content =~ "Tool error"
  end

  test "records tool errors when tool exits" do
    exiting_tool =
      %Tool{
        name: "echo",
        description: "exits",
        parameters: %{},
        execute: fn _args, _env -> exit(:bad_exit) end
      }

    completed = Session.submit(build_session("single_tool", [exiting_tool]), "run")
    tool_turn = Enum.find(completed.history, &(&1.type == :tool_results))
    [result] = tool_turn.results

    assert result.is_error
    assert result.content =~ "Tool error"
  end

  test "closes session on llm error" do
    profile =
      ProviderProfile.new(
        id: "openai",
        model: "gpt-5.2",
        tools: [echo_tool()],
        provider_options: %{"scenario" => "unused"}
      )

    client = %Client{providers: %{"openai" => AttractorExTest.LLMErrorAdapter}}

    session =
      Session.new(client, profile,
        execution_env: LocalExecutionEnvironment.new(working_dir: File.cwd!())
      )

    completed = Session.submit(session, "error please")

    assert completed.state == :closed

    assert Enum.any?(completed.history, fn turn ->
             turn.type == :system and String.contains?(turn.content, "LLM error")
           end)
  end

  test "llm error does not drop queued follow-up input" do
    profile =
      ProviderProfile.new(
        id: "openai",
        model: "gpt-5.2",
        tools: [echo_tool()],
        provider_options: %{"scenario" => "unused"}
      )

    client = %Client{providers: %{"openai" => AttractorExTest.LLMErrorAdapter}}

    session =
      Session.new(client, profile,
        execution_env: LocalExecutionEnvironment.new(working_dir: File.cwd!())
      )
      |> Session.follow_up("second prompt")

    completed = Session.submit(session, "first prompt")

    assert completed.state == :closed
    assert :queue.to_list(completed.followup_queue) == ["second prompt"]
  end

  test "uses cwd fallback when execution env is not local env struct" do
    profile =
      ProviderProfile.new(
        id: "openai",
        model: "gpt-5.2",
        tools: [echo_tool()],
        provider_options: %{"scenario" => "no_tools"}
      )

    client = %Client{providers: %{"openai" => AttractorExTest.AgentAdapter}}
    session = Session.new(client, profile, execution_env: %{}, config: [])
    completed = Session.submit(session, "hello")

    assert completed.state == :idle
  end

  test "rejects invalid tool arguments before executing tool" do
    validating_tool =
      %Tool{
        name: "echo",
        description: "requires text",
        parameters: %{
          "type" => "object",
          "properties" => %{"text" => %{"type" => "string"}},
          "required" => ["text"]
        },
        execute: fn _args, _env -> flunk("tool should not execute with invalid args") end
      }

    completed =
      Session.submit(build_session("single_tool_numeric_args", [validating_tool]), "run")

    tool_turn = Enum.find(completed.history, &(&1.type == :tool_results))
    [result] = tool_turn.results

    assert result.is_error
    assert result.content =~ "invalid arguments"
  end

  test "rejects wrong tool argument types before executing tool" do
    validating_tool =
      %Tool{
        name: "echo",
        description: "requires integer timeout",
        parameters: %{
          "type" => "object",
          "properties" => %{"timeout_ms" => %{"type" => "integer"}},
          "required" => ["timeout_ms"]
        },
        execute: fn _args, _env -> flunk("tool should not execute with invalid args") end
      }

    completed =
      Session.submit(
        build_session("single_tool_wrong_type_args", [validating_tool]),
        "run"
      )

    tool_turn = Enum.find(completed.history, &(&1.type == :tool_results))
    [result] = tool_turn.results

    assert result.is_error
    assert result.content =~ "wrong type"
  end

  test "loads AGENTS and provider-specific instructions into system prompt context" do
    root =
      Path.join(System.tmp_dir!(), "attractor-agent-docs-#{System.unique_integer([:positive])}")

    nested = Path.join(root, "nested")
    File.mkdir_p!(Path.join(root, ".codex"))
    File.mkdir_p!(nested)
    File.write!(Path.join(root, "AGENTS.md"), "Repo instructions")
    File.write!(Path.join(root, "CODEX.md"), "Provider instructions")
    File.write!(Path.join([root, ".codex", "instructions.md"]), "Codex instructions")

    completed =
      Session.submit(
        build_session("echo_system_prompt", [echo_tool()],
          execution_env: LocalExecutionEnvironment.new(working_dir: nested)
        ),
        "show prompt"
      )

    assert last_assistant_text(completed) =~ "Repo instructions"
    assert last_assistant_text(completed) =~ "Provider instructions"
    assert last_assistant_text(completed) =~ "Codex instructions"
  end

  test "anthropic and gemini instruction discovery use provider-specific filenames" do
    root =
      Path.join(
        System.tmp_dir!(),
        "attractor-agent-provider-docs-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(root)
    File.write!(Path.join(root, "CLAUDE.md"), "Anthropic instructions")
    File.write!(Path.join(root, "GEMINI.md"), "Gemini instructions")

    anthropic_profile =
      ProviderProfile.new(
        id: "anthropic",
        model: "claude-sonnet",
        tools: [echo_tool()],
        provider_options: %{"scenario" => "echo_system_prompt"}
      )

    gemini_profile =
      ProviderProfile.new(
        id: "gemini",
        model: "gemini-pro",
        tools: [echo_tool()],
        provider_options: %{"scenario" => "echo_system_prompt"}
      )

    client = %Client{
      providers: %{
        "anthropic" => AttractorExTest.AgentAdapter,
        "gemini" => AttractorExTest.AgentAdapter
      }
    }

    anthropic =
      Session.new(client, anthropic_profile,
        execution_env: LocalExecutionEnvironment.new(working_dir: root)
      )
      |> Session.submit("docs")

    gemini =
      Session.new(client, gemini_profile,
        execution_env: LocalExecutionEnvironment.new(working_dir: root)
      )
      |> Session.submit("docs")

    assert last_assistant_text(anthropic) =~ "Anthropic instructions"
    assert last_assistant_text(gemini) =~ "Gemini instructions"
  end

  test "emits context warning when request nears configured context window" do
    profile =
      ProviderProfile.new(
        id: "openai",
        model: "gpt-5.2",
        context_window_size: 40,
        tools: [echo_tool()],
        provider_options: %{"scenario" => "no_tools"}
      )

    client = %Client{providers: %{"openai" => AttractorExTest.AgentAdapter}}

    session =
      Session.new(client, profile,
        execution_env: LocalExecutionEnvironment.new(working_dir: File.cwd!())
      )

    completed = Session.submit(session, String.duplicate("x", 50))

    assert Enum.any?(completed.events, fn event ->
             event.kind == :context_warning and event.payload[:context_window_size] == 40
           end)
  end

  defp build_session(scenario, tools, opts \\ []) do
    config_overrides = Keyword.get(opts, :config, [])

    profile =
      ProviderProfile.new(
        id: "openai",
        model: "gpt-5.2",
        tools: tools,
        supports_parallel_tool_calls: Keyword.get(opts, :supports_parallel, false),
        provider_options: %{"scenario" => scenario}
      )

    client = %Client{providers: %{"openai" => AttractorExTest.AgentAdapter}}

    Session.new(client, profile,
      execution_env:
        Keyword.get(opts, :execution_env, LocalExecutionEnvironment.new(working_dir: File.cwd!())),
      config: config_overrides
    )
  end

  defp echo_tool do
    %Tool{
      name: "echo",
      description: "echo input text",
      parameters: %{},
      execute: fn args, _env -> args["text"] || "" end
    }
  end

  defp slow_tool do
    %Tool{
      name: "slow",
      description: "slow tool",
      parameters: %{},
      execute: fn args, _env ->
        Process.sleep(300)
        args["text"] || ""
      end
    }
  end

  defp event_kinds(session), do: Enum.map(session.events, & &1.kind)

  defp last_assistant_text(session) do
    session.history
    |> Enum.filter(&(&1.type == :assistant))
    |> List.last()
    |> Map.get(:content)
  end
end
