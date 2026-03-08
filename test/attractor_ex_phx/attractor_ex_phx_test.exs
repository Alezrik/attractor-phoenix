defmodule AttractorExPhxTest do
  use ExUnit.Case, async: false

  test "run/3 delegates to AttractorEx" do
    dot = """
    digraph attractor {
      start [shape=Mdiamond]
      hello [shape=parallelogram, tool_command="echo hello"]
      done [shape=Msquare]
      start -> hello
      hello -> done
    }
    """

    assert {:ok, result} = AttractorExPhx.run(dot, %{}, logs_root: unique_logs_root())
    assert result.status == :success
  end

  test "child_spec/1 uses the configured server name as its id" do
    assert %{
             id: DemoHTTPServer,
             start: {AttractorExPhx.HTTPServer, :start_link, [[name: DemoHTTPServer]]}
           } =
             AttractorExPhx.child_spec(name: DemoHTTPServer)
  end

  defp unique_logs_root do
    Path.join([
      "tmp",
      "attractor_ex_phx_test",
      Integer.to_string(System.unique_integer([:positive]))
    ])
  end
end
