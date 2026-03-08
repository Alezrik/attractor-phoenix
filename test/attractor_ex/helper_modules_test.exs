defmodule AttractorEx.HelperModulesTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  alias AttractorEx.Interviewers.{Console, Queue, Recording}
  alias AttractorEx.LLM.MessagePart
  alias AttractorEx.{Edge, Graph, HandlerRegistry, HumanGate, Node}

  test "human gate matches keys labels and destinations across accelerator styles" do
    graph = %Graph{
      edges: [
        Edge.new("gate", "approved", %{"label" => "Y) Yes"}),
        Edge.new("gate", "rejected", %{"label" => "N - No"}),
        Edge.new("gate", "later", %{"label" => "[L] Later"}),
        Edge.new("gate", "fallback", %{"label" => ""})
      ]
    }

    choices = HumanGate.choices_for("gate", graph)

    assert Enum.map(choices, & &1.key) == ["Y", "N", "L", "F"]
    assert HumanGate.match_choice("y", choices).to == "approved"
    assert HumanGate.match_choice("Y) Yes", choices).to == "approved"
    assert HumanGate.match_choice("n", choices).to == "rejected"
    assert HumanGate.match_choice("later", choices).to == "later"
    assert HumanGate.match_choice("fallback", choices).to == "fallback"
    assert HumanGate.normalize_token(nil) == ""
  end

  test "human gate falls back to empty accelerator key for blank labels" do
    graph = %Graph{edges: [Edge.new("gate", "blank", %{"label" => "   "})]}
    assert [%{key: "", label: "   ", to: "blank"}] = HumanGate.choices_for("gate", graph)
  end

  test "handler registry resolves registered explicit types and shape fallbacks" do
    unique_type = "custom.type.#{System.unique_integer([:positive])}"
    :ok = HandlerRegistry.register(unique_type, AttractorEx.Handlers.Tool)

    explicit = Node.new("n1", %{"type" => "  #{unique_type}  "})
    shape_based = Node.new("n2", %{"shape" => "parallelogram"})
    fallback = Node.new("n3", %{"shape" => "box"})

    assert HandlerRegistry.resolve(explicit) == AttractorEx.Handlers.Tool
    assert HandlerRegistry.handler_for(shape_based) == AttractorEx.Handlers.Tool
    assert HandlerRegistry.resolve(fallback) == AttractorEx.Handlers.Codergen
    assert HandlerRegistry.known_type?("  #{unique_type} ")
    refute HandlerRegistry.known_type?(123)
  end

  test "queue interviewer preserves timeout results through ask_multiple" do
    queue = start_supervised!({Agent, fn -> [] end})

    assert {:timeout} = Queue.ask_multiple(%Node{}, [], %{}, queue: queue)
  end

  test "recording interviewer returns :ok when inner ask callback is unavailable" do
    sink = start_supervised!({Agent, fn -> [] end})

    assert :ok =
             Recording.ask(
               %Node{id: "gate"},
               [%{key: "A", label: "Approve", to: "done"}],
               %{},
               inner: AttractorEx.Graph,
               recording_sink: sink
             )

    events = Agent.get(sink, & &1)
    assert Enum.any?(events, &(&1.event == :ask))
    refute Enum.any?(events, &(&1.event == :answer))
  end

  test "recording interviewer preserves non-ok ask_multiple fallback results" do
    assert :timeout =
             Recording.ask_multiple(
               %Node{id: "gate"},
               [%{key: "A", label: "Approve", to: "done"}],
               %{},
               inner: AttractorExTest.AskOnlyTimeoutInterviewer
             )
  end

  test "recording interviewer normalizes ask_multiple through ask fallback and records answer" do
    sink = start_supervised!({Agent, fn -> [] end})

    assert {:ok, ["A", "fixes"]} =
             Recording.ask_multiple(
               %Node{id: "gate"},
               [
                 %{key: "A", label: "Approve", to: "approved"},
                 %{key: "F", label: "Fix", to: "fixes"}
               ],
               %{},
               inner: AttractorExTest.AskOnlyAnswerInterviewer,
               recording_sink: sink,
               answer: %{"selected" => [%{"key" => "A"}, "fixes"]}
             )

    events = Agent.get(sink, & &1)
    assert Enum.any?(events, &(&1.event == :ask_multiple))

    assert Enum.any?(events, fn
             %{event: :answer, answer: ["A", "fixes"]} -> true
             _ -> false
           end)
  end

  test "recording interviewer informs through callback inner" do
    test_pid = self()

    assert :ok =
             Recording.inform(
               %Node{id: "gate"},
               %{"message" => "Heads up"},
               %{"ctx" => true},
               inner: :callback,
               callback_inform: fn node, payload, context ->
                 send(test_pid, {:informed, node.id, payload, context})
                 :ok
               end
             )

    assert_receive {:informed, "gate", %{"message" => "Heads up"}, %{"ctx" => true}}
  end

  test "recording interviewer resolves console inner for inform fallback" do
    assert :ok =
             Recording.inform(
               %Node{id: "gate"},
               %{"message" => "Heads up"},
               %{},
               inner: :console
             )
  end

  test "recording interviewer swallows sink errors and preserves answer result" do
    assert {:ok, "A"} =
             Recording.ask(
               %Node{id: "gate"},
               [%{key: "A", label: "Approve", to: "done"}],
               %{},
               inner: :callback,
               recording_sink: fn _event -> raise "sink boom" end,
               callback: fn _node, _choices, _context -> {:ok, "A"} end
             )
  end

  test "console interviewer prints integer timeout and inferred input mode" do
    output =
      capture_io("A\n", fn ->
        assert {:ok, "A"} =
                 Console.ask(
                   %Node{id: "gate", attrs: %{"human.timeout" => 15}},
                   [%{key: "A", label: "Approve", to: "done"}],
                   %{},
                   []
                 )
      end)

    assert output =~ "Timeout: 15"
    assert output =~ "Input: confirmation"
  end

  test "console interviewer ask_multiple returns timeout on eof input" do
    output =
      capture_io("", fn ->
        assert {:timeout} =
                 Console.ask_multiple(
                   %Node{id: "gate", attrs: %{"human.multiple" => true}},
                   [%{key: "A", label: "Approve", to: "done"}],
                   %{},
                   []
                 )
      end)

    assert output =~ "Enter comma-separated keys or JSON payload."
  end

  test "callback interviewer inform returns ok without callback" do
    assert :ok = AttractorEx.Interviewers.Callback.inform(%Node{}, %{}, %{}, [])
  end

  test "stream error adapter exposes its non-stream complete error" do
    assert {:error, :unused} =
             AttractorExTest.StreamErrorAdapter.complete(%AttractorEx.LLM.Request{})
  end

  test "message part projection covers known binary type mappings" do
    assert MessagePart.text_projection(%{"type" => "text", "text" => "hello"}) == "hello"
    assert MessagePart.text_projection(%{"type" => "image"}) == "[image]"
    assert MessagePart.text_projection(%{"type" => "audio"}) == "[audio]"
    assert MessagePart.text_projection(%{"type" => "document"}) == "[document]"
    assert MessagePart.text_projection(%{"type" => "tool_call"}) == "[tool call]"
    assert MessagePart.text_projection(%{"type" => "tool_result"}) == "[tool result]"
    assert MessagePart.text_projection(%{"type" => "json"}) == "[json]"
  end

  test "message part projection normalizes unsupported type shapes to text" do
    assert MessagePart.text_projection(%{"type" => 123, "text" => "fallback"}) == "fallback"
  end
end
