defmodule AttractorEx.Conformance.AgentLoopTest do
  use ExUnit.Case, async: true

  alias AttractorEx.Agent.Session
  alias AttractorExTest.ConformanceFixtures

  test "provider preset executes a tool round and emits the maintained event surface" do
    completed =
      "single_tool"
      |> ConformanceFixtures.build_agent_session()
      |> Session.submit("run tool")

    assert completed.state == :idle
    assert Enum.any?(completed.events, &(&1.kind == :session_start))
    assert Enum.any?(completed.events, &(&1.kind == :tool_call_start))
    assert Enum.any?(completed.events, &(&1.kind == :tool_call_end))

    assert Enum.any?(
             completed.history,
             &(&1.type == :assistant and &1.content == "tool-complete")
           )
  end

  test "project instructions are layered into the session prompt context" do
    root =
      Path.join(
        System.tmp_dir!(),
        "attractor_conformance_agent_#{System.unique_integer([:positive])}"
      )

    nested = Path.join(root, "nested")
    File.mkdir_p!(Path.join(root, ".codex"))
    File.mkdir_p!(nested)
    File.write!(Path.join(root, "AGENTS.md"), "Repo instructions")
    File.write!(Path.join(root, "CODEX.md"), "Provider instructions")
    File.write!(Path.join([root, ".codex", "instructions.md"]), "Codex instructions")

    completed =
      Session.submit(
        ConformanceFixtures.build_agent_session("echo_system_prompt")
        |> Map.put(
          :execution_env,
          AttractorEx.Agent.LocalExecutionEnvironment.new(working_dir: nested)
        ),
        "show prompt"
      )

    prompt =
      completed.history
      |> Enum.filter(&(&1.type == :assistant))
      |> List.last()
      |> Map.fetch!(:content)

    assert prompt =~ "Repo instructions"
    assert prompt =~ "Provider instructions"
    assert prompt =~ "Codex instructions"
  end
end
