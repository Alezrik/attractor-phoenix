defmodule AttractorEx.Agent.SessionTest do
  use ExUnit.Case, async: true

  alias AttractorEx.Agent.{
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

  test "parallel tool calls execute concurrently when profile allows it" do
    session = build_session("parallel_tools", [slow_tool()], supports_parallel: true)

    {elapsed_us, completed} =
      :timer.tc(fn ->
        Session.submit(session, "parallel")
      end)

    assert elapsed_us < 400_000
    assert last_assistant_text(completed) == "parallel-done"
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

    assert result.content =~ "[WARNING: Tool output was truncated."
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
      execution_env: LocalExecutionEnvironment.new(working_dir: File.cwd!()),
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
        Process.sleep(220)
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
