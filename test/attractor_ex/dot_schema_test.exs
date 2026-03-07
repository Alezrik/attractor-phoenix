defmodule AttractorEx.DotSchemaTest do
  use ExUnit.Case, async: true

  alias AttractorEx.{Parser, Validator}

  describe "2.1/2.2 supported subset and grammar" do
    test "parses graph attrs, node defaults, edge defaults, node and edge statements" do
      dot = """
      digraph attractor {
        graph [goal="Ship feature", default_max_retry=50]
        node [shape=box, timeout="900s"]
        edge [weight=0]

        start [shape=Mdiamond]
        task [label="Task"]
        done [shape=Msquare]

        start -> task -> done [label="next"]
      }
      """

      assert {:ok, graph} = Parser.parse(dot)
      assert graph.attrs["goal"] == "Ship feature"
      assert graph.attrs["default_max_retry"] == 50
      assert graph.nodes["task"].attrs["timeout"] == "900s"
      assert Enum.at(graph.edges, 0).attrs["label"] == "next"
      assert Enum.at(graph.edges, 1).attrs["label"] == "next"
    end

    test "supports graph attribute declarations as key=value" do
      dot = """
      digraph attractor {
        goal="Hello World"
        label="hello-world"
        start [shape=Mdiamond]
        done [shape=Msquare]
        start -> done
      }
      """

      assert {:ok, graph} = Parser.parse(dot)
      assert graph.attrs["goal"] == "Hello World"
      assert graph.attrs["label"] == "hello-world"
    end
  end

  describe "2.3 key constraints" do
    test "rejects undirected edges" do
      dot = """
      digraph attractor {
        a -- b
      }
      """

      assert {:error, message} = Parser.parse(dot)
      assert message =~ "Undirected edges are not supported"
    end

    test "accepts semicolons as optional" do
      dot = """
      digraph attractor {
        start [shape=Mdiamond];
        done [shape=Msquare]
        start -> done;
      }
      """

      assert {:ok, graph} = Parser.parse(dot)
      assert Map.has_key?(graph.nodes, "start")
      assert length(graph.edges) == 1
    end

    test "supports repeated attribute blocks and semicolon-separated attrs inside blocks" do
      dot = """
      digraph attractor {
        node [shape=box; timeout="900s"][class="core"]
        edge [label="next"; weight=1][fidelity="full"]
        start [shape=Mdiamond]
        task [prompt="Plan"]
        done [shape=Msquare]
        start -> task -> done
      }
      """

      assert {:ok, graph} = Parser.parse(dot)
      assert graph.nodes["task"].attrs["timeout"] == "900s"
      assert graph.nodes["task"].attrs["class"] == "core"
      assert Enum.all?(graph.edges, &(&1.attrs["label"] == "next"))
      assert Enum.all?(graph.edges, &(&1.attrs["weight"] == 1))
      assert Enum.all?(graph.edges, &(&1.attrs["fidelity"] == "full"))
    end

    test "supports multiline attribute blocks without explicit separators" do
      dot = """
      digraph attractor {
        node [
          shape=box
          timeout="900s"
          class="core"
        ]
        edge [
          label="next"
          weight=1
        ]

        start [shape=Mdiamond]
        task [prompt="Plan"]
        done [shape=Msquare]
        start -> task -> done
      }
      """

      assert {:ok, graph} = Parser.parse(dot)
      assert graph.nodes["task"].attrs["timeout"] == "900s"
      assert graph.nodes["task"].attrs["class"] == "core"
      assert Enum.all?(graph.edges, &(&1.attrs["label"] == "next"))
      assert Enum.all?(graph.edges, &(&1.attrs["weight"] == 1))
    end

    test "strips line and block comments" do
      dot = """
      digraph attractor {
        // line comment
        /* block
           comment */
        start [shape=Mdiamond]
        done [shape=Msquare]
        start -> done
      }
      """

      assert {:ok, graph} = Parser.parse(dot)
      assert Map.has_key?(graph.nodes, "start")
      assert Map.has_key?(graph.nodes, "done")
    end

    test "enforces bare identifier node ids" do
      dot = """
      digraph attractor {
        bad-node [shape=box]
      }
      """

      assert {:error, message} = Parser.parse(dot)
      assert message =~ "Invalid node declaration"
    end
  end

  describe "2.4 value types" do
    test "parses string, integer, float, boolean, duration syntax values" do
      dot = """
      digraph attractor {
        graph [goal="Hello", default_max_retry=50]
        node [max_retries=3, goal_gate=true, timeout="900s", ratio=0.5]
        start [shape=Mdiamond]
        task [shape=box]
        done [shape=Msquare]
        start -> task -> done
      }
      """

      assert {:ok, graph} = Parser.parse(dot)
      assert graph.attrs["default_max_retry"] == 50
      assert graph.nodes["task"].attrs["max_retries"] == 3
      assert graph.nodes["task"].attrs["goal_gate"] == true
      assert graph.nodes["task"].attrs["timeout"] == "900s"
      assert graph.nodes["task"].attrs["ratio"] == 0.5
    end
  end

  describe "2.5-2.8 attrs and shape mapping" do
    test "parses graph, node, and edge attributes used by engine" do
      dot = """
      digraph attractor {
        graph [goal="Hello", retry_target="task", fallback_retry_target="done", default_fidelity="full"]
        start [shape=Mdiamond]
        task [shape=box, prompt="Do work", class="critical", max_retries=2, goal_gate=true]
        done [shape=Msquare]
        start -> task [label="go", condition="outcome.status == \\"success\\"", weight=10, fidelity="full", thread_id="main", loop_restart=false]
        task -> done
      }
      """

      assert {:ok, graph} = Parser.parse(dot)
      assert graph.attrs["retry_target"] == "task"
      assert graph.nodes["task"].attrs["class"] == "critical"
      assert graph.nodes["task"].attrs["goal_gate"] == true
      assert Enum.at(graph.edges, 0).attrs["weight"] == 10
      assert Enum.at(graph.edges, 0).attrs["loop_restart"] == false
    end

    test "uses canonical shape-to-handler mapping" do
      dot = """
      digraph attractor {
        start [shape=Mdiamond]
        exit [shape=Msquare]
        llm [shape=box]
        human [shape=hexagon]
        cond [shape=diamond]
        par [shape=component]
        fanin [shape=tripleoctagon]
        tool [shape=parallelogram]
        manager [shape=house]
      }
      """

      assert {:ok, graph} = Parser.parse(dot)
      assert graph.nodes["start"].type == "start"
      assert graph.nodes["exit"].type == "exit"
      assert graph.nodes["llm"].type == "codergen"
      assert graph.nodes["human"].type == "wait.human"
      assert graph.nodes["cond"].type == "conditional"
      assert graph.nodes["par"].type == "parallel"
      assert graph.nodes["fanin"].type == "parallel.fan_in"
      assert graph.nodes["tool"].type == "tool"
      assert graph.nodes["manager"].type == "stack.manager_loop"
    end
  end

  describe "2.9-2.13 chained edges, defaults, class, and examples" do
    test "applies edge attrs to every edge in chained declarations" do
      dot = """
      digraph attractor {
        start [shape=Mdiamond]
        a [shape=box]
        b [shape=box]
        done [shape=Msquare]
        start -> a -> b -> done [label="next", status="success"]
      }
      """

      assert {:ok, graph} = Parser.parse(dot)
      assert length(graph.edges) == 3
      assert Enum.all?(graph.edges, &(&1.attrs["label"] == "next"))
      assert Enum.all?(graph.edges, &(&1.attrs["status"] == "success"))
    end

    test "node and edge default blocks are inherited and can be overridden" do
      dot = """
      digraph attractor {
        node [shape=box, timeout="900s"]
        edge [weight=0]
        start [shape=Mdiamond]
        task [timeout="1800s"]
        done [shape=Msquare]
        start -> task [weight=7]
        task -> done
      }
      """

      assert {:ok, graph} = Parser.parse(dot)
      assert graph.nodes["task"].attrs["timeout"] == "1800s"
      assert Enum.at(graph.edges, 0).attrs["weight"] == 7
      assert Enum.at(graph.edges, 1).attrs["weight"] == 0
    end

    test "parses class attribute for stylesheet targeting" do
      dot = """
      digraph attractor {
        start [shape=Mdiamond]
        review_code [shape=box, class="code,critical", prompt="Review the code"]
        done [shape=Msquare]
        start -> review_code -> done
      }
      """

      assert {:ok, graph} = Parser.parse(dot)
      assert graph.nodes["review_code"].attrs["class"] == "code,critical"
    end

    test "minimal linear example validates" do
      dot = """
      digraph Simple {
        graph [goal="Run tests and report"]
        rankdir=LR
        start [shape=Mdiamond, label="Start"]
        exit [shape=Msquare, label="Exit"]
        run_tests [label="Run Tests", prompt="Run the test suite and report results"]
        report [label="Report", prompt="Summarize the test results"]
        start -> run_tests -> report -> exit
      }
      """

      assert {:ok, graph} = Parser.parse(dot)
      diagnostics = Validator.validate(graph)
      refute Enum.any?(diagnostics, &(&1.severity == :error))
    end
  end
end
