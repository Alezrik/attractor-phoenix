defmodule AttractorEx.Conformance.ParsingTest do
  use ExUnit.Case, async: true

  alias AttractorEx
  alias AttractorEx.Parser
  alias AttractorExTest.ConformanceFixtures

  test "accepts the supported DOT subset through the public parsing surface" do
    assert {:ok, graph} = Parser.parse(ConformanceFixtures.parsing_dot())
    assert Map.has_key?(graph.nodes, "plan")
    assert [] == AttractorEx.validate(graph)
  end

  test "rejects malformed non-digraph input with an explicit parse error" do
    assert {:error, message} = Parser.parse(ConformanceFixtures.invalid_dot())
    assert message =~ "Invalid DOT input"
  end
end
