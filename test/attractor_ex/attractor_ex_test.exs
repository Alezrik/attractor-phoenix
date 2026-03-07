defmodule AttractorExTest do
  use ExUnit.Case, async: true

  alias AttractorEx.{Graph, Node}

  describe "public validation API" do
    test "validate/2 accepts a graph struct" do
      graph = %Graph{
        nodes: %{
          "start" => Node.new("start", %{"shape" => "Mdiamond"}),
          "done" => Node.new("done", %{"shape" => "Msquare"})
        },
        edges: []
      }

      diagnostics = AttractorEx.validate(graph)
      assert is_list(diagnostics)
    end

    test "validate/2 parses dot input and returns parser errors" do
      assert {:error, %{error: message}} = AttractorEx.validate("not dot")
      assert message =~ "Invalid DOT input"
    end

    test "validate/2 parses valid dot input" do
      dot = """
      digraph attractor {
        start [shape=Mdiamond]
        done [shape=Msquare]
        start -> done
      }
      """

      diagnostics = AttractorEx.validate(dot)
      assert is_list(diagnostics)
    end

    test "validate_or_raise/2 accepts a graph struct" do
      graph = %Graph{
        nodes: %{
          "start" => Node.new("start", %{"shape" => "Mdiamond"}),
          "done" => Node.new("done", %{"shape" => "Msquare"})
        },
        edges: [AttractorEx.Edge.new("start", "done", %{})]
      }

      diagnostics = AttractorEx.validate_or_raise(graph)
      assert is_list(diagnostics)
    end

    test "validate_or_raise/2 raises on parse errors for dot input" do
      assert_raise ArgumentError, ~r/Attractor parse failed/, fn ->
        AttractorEx.validate_or_raise("not dot")
      end
    end

    test "validate_or_raise/2 parses valid dot input" do
      dot = """
      digraph attractor {
        start [shape=Mdiamond]
        done [shape=Msquare]
        start -> done
      }
      """

      diagnostics = AttractorEx.validate_or_raise(dot)
      assert is_list(diagnostics)
    end
  end
end
