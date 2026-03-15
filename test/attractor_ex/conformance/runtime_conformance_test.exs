defmodule AttractorEx.Conformance.RuntimeTest do
  use ExUnit.Case, async: true

  alias AttractorEx
  alias AttractorExTest.ConformanceFixtures

  test "executes a pipeline and emits expected run artifacts" do
    assert {:ok, result} =
             AttractorEx.run(ConformanceFixtures.runtime_dot(), %{},
               logs_root: ConformanceFixtures.unique_logs_root("runtime"),
               codergen_backend: AttractorExTest.EchoBackend
             )

    assert result.status == :success
    assert File.exists?(Path.join(result.logs_root, "checkpoint.json"))
    assert File.exists?(Path.join([result.logs_root, "plan", "status.json"]))
    assert File.exists?(Path.join([result.logs_root, "implement", "response.md"]))
  end

  test "resumes a pipeline from checkpoint.json using the public API" do
    assert {:ok, interrupted} =
             AttractorEx.run(ConformanceFixtures.runtime_dot(), %{},
               logs_root: ConformanceFixtures.unique_logs_root("resume"),
               codergen_backend: AttractorExTest.EchoBackend,
               max_steps: 2
             )

    checkpoint_path = Path.join(interrupted.logs_root, "checkpoint.json")

    assert {:ok, resumed} =
             AttractorEx.resume(ConformanceFixtures.runtime_dot(), checkpoint_path,
               codergen_backend: AttractorExTest.EchoBackend,
               max_steps: 10
             )

    assert resumed.status == :success
    assert resumed.context["run_id"] == interrupted.context["run_id"]
  end
end
