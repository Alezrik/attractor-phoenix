defmodule AttractorEx.InterviewersTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  alias AttractorEx.Interviewers.{AutoApprove, Callback, Console, Queue, Recording}
  alias AttractorEx.Node

  describe "auto approve interviewer" do
    test "uses configured choice when provided" do
      assert {:ok, "F"} = AutoApprove.ask(%Node{}, [], %{}, choice: "F")
    end

    test "falls back to first choice key and then `to`" do
      assert {:ok, "A"} =
               AutoApprove.ask(%Node{}, [%{key: "A", label: "Approve", to: "done"}], %{}, [])

      assert {:ok, "done"} = AutoApprove.ask(%Node{}, [%{label: "Approve", to: "done"}], %{}, [])
    end

    test "returns timeout when no choices are available" do
      assert {:timeout} = AutoApprove.ask(%Node{}, [], %{}, [])
    end

    test "supports multi-select responses" do
      assert {:ok, ["A"]} =
               AutoApprove.ask_multiple(
                 %Node{},
                 [%{key: "A", label: "Approve", to: "done"}],
                 %{},
                 []
               )
    end
  end

  describe "callback interviewer" do
    test "supports arity-3 callbacks" do
      callback = fn _node, _choices, _context -> {:ok, "A"} end
      assert {:ok, "A"} = Callback.ask(%Node{}, [], %{}, callback: callback)
    end

    test "supports arity-4 callbacks" do
      callback = fn _node, _choices, _context, opts -> {:ok, opts[:choice]} end
      assert {:ok, "B"} = Callback.ask(%Node{}, [], %{}, callback: callback, choice: "B")
    end

    test "returns error when callback is missing" do
      assert {:error, _} = Callback.ask(%Node{}, [], %{}, [])
    end

    test "supports ask_multiple and inform callbacks" do
      multiple = fn _node, _choices, _context -> {:ok, ["A", "B"]} end
      inform = fn _node, payload, _context -> {:ok, payload[:message]} end

      assert {:ok, ["A", "B"]} =
               Callback.ask_multiple(%Node{}, [], %{}, callback_multiple: multiple)

      assert {:ok, "done"} =
               Callback.inform(%Node{}, %{message: "done"}, %{}, callback_inform: inform)
    end

    test "supports arity-4 ask_multiple and inform callbacks" do
      multiple = fn _node, _choices, _context, opts -> {:ok, opts[:choices]} end

      inform = fn _node, payload, _context, opts ->
        {:ok, "#{payload[:message]}-#{opts[:suffix]}"}
      end

      assert {:ok, ["A", "B"]} =
               Callback.ask_multiple(%Node{}, [], %{},
                 callback_multiple: multiple,
                 choices: ["A", "B"]
               )

      assert {:ok, "done-ok"} =
               Callback.inform(%Node{}, %{message: "done"}, %{},
                 callback_inform: inform,
                 suffix: "ok"
               )
    end

    test "returns error when ask_multiple callback is missing" do
      assert {:error, _} = Callback.ask_multiple(%Node{}, [], %{}, [])
    end
  end

  describe "console interviewer" do
    test "reads a user answer from stdin" do
      output =
        capture_io("A\n", fn ->
          assert {:ok, "A"} =
                   Console.ask(
                     %Node{id: "gate"},
                     [%{key: "A", label: "Approve", to: "done"}],
                     %{},
                     []
                   )
        end)

      assert output =~ "Select a choice for human gate"
    end

    test "prints prompt, default choice, and timeout metadata when configured" do
      output =
        capture_io("F\n", fn ->
          assert {:ok, "F"} =
                   Console.ask(
                     %Node{
                       id: "gate",
                       attrs: %{
                         "prompt" => "Review the release checklist",
                         "human.default_choice" => "fixes",
                         "human.timeout" => "30s"
                       }
                     },
                     [%{key: "F", label: "[F] Fix", to: "fixes"}],
                     %{},
                     []
                   )
        end)

      assert output =~ "Prompt: Review the release checklist"
      assert output =~ "Default: fixes"
      assert output =~ "Timeout: 30s"
    end

    test "returns timeout when no stdin is available" do
      _output =
        capture_io("", fn ->
          assert {:timeout} =
                   Console.ask(
                     %Node{id: "gate"},
                     [%{key: "A", label: "Approve", to: "done"}],
                     %{},
                     []
                   )
        end)
    end

    test "supports comma-separated multi-select answers" do
      _output =
        capture_io("A, B\n", fn ->
          assert {:ok, ["A", "B"]} =
                   Console.ask_multiple(
                     %Node{id: "gate"},
                     [%{key: "A", label: "Approve", to: "done"}],
                     %{},
                     []
                   )
        end)
    end

    test "prints informational messages" do
      output =
        capture_io(fn ->
          assert :ok = Console.inform(%Node{id: "gate"}, %{message: "Heads up"}, %{}, [])
        end)

      assert output =~ "Info for `gate`: Heads up"
    end
  end

  describe "queue interviewer" do
    test "reads from list queues and supports empty queues" do
      assert {:ok, "A"} = Queue.ask(%Node{}, [], %{}, queue: ["A", "B"])
      assert {:timeout} = Queue.ask(%Node{}, [], %{}, queue: [])
    end

    test "reads and pops from agent queues" do
      queue = start_supervised!({Agent, fn -> ["A", "B"] end})
      assert {:ok, "A"} = Queue.ask(%Node{}, [], %{}, queue: queue)
      assert Agent.get(queue, & &1) == ["B"]
    end

    test "returns timeout for empty agent queues" do
      queue = start_supervised!({Agent, fn -> [] end})
      assert {:timeout} = Queue.ask(%Node{}, [], %{}, queue: queue)
    end

    test "returns error for unsupported queue values in agent" do
      queue = start_supervised!({Agent, fn -> %{value: "bad"} end})
      assert {:error, _} = Queue.ask(%Node{}, [], %{}, queue: queue)
    end

    test "returns error when queue is invalid" do
      assert {:error, _} = Queue.ask(%Node{}, [], %{}, queue: :invalid)
    end

    test "supports multi-select answers from queued lists" do
      assert {:ok, ["A", "B"]} = Queue.ask_multiple(%Node{}, [], %{}, queue: [["A", "B"]])
    end

    test "wraps single queued answers for ask_multiple and supports inform" do
      assert {:ok, ["A"]} = Queue.ask_multiple(%Node{}, [], %{}, queue: ["A"])
      assert :ok = Queue.inform(%Node{}, %{message: "ignored"}, %{}, [])
    end
  end

  describe "recording interviewer" do
    test "records ask and inform events while delegating to the inner interviewer" do
      sink = start_supervised!({Agent, fn -> [] end})

      assert {:ok, "A"} =
               Recording.ask(
                 %Node{id: "gate"},
                 [%{key: "A", label: "Approve", to: "done"}],
                 %{},
                 inner: :auto_approve,
                 recording_sink: sink
               )

      assert :ok =
               Recording.inform(
                 %Node{id: "gate"},
                 %{message: "record this"},
                 %{},
                 inner: :auto_approve,
                 recording_sink: sink
               )

      events = Agent.get(sink, & &1)
      assert Enum.any?(events, &(&1.event == :ask and &1.node_id == "gate"))
      assert Enum.any?(events, &(&1.event == :inform and &1.node_id == "gate"))
    end

    test "records ask_multiple and falls back to inner ask when needed" do
      sink = start_supervised!({Agent, fn -> [] end})

      assert {:ok, ["A"]} =
               Recording.ask_multiple(
                 %Node{id: "gate"},
                 [%{key: "A", label: "Approve", to: "done"}],
                 %{},
                 inner: :auto_approve,
                 recording_sink: sink
               )

      events = Agent.get(sink, & &1)
      assert Enum.any?(events, &(&1.event == :ask_multiple and &1.node_id == "gate"))
    end

    test "supports function recording sinks and callback inner delegates" do
      parent = self()

      sink = fn event ->
        send(parent, {:recorded, event})
      end

      callback = fn _node, _choices, _context -> {:ok, "F"} end

      assert {:ok, "F"} =
               Recording.ask(
                 %Node{id: "gate"},
                 [%{key: "F", label: "Fix", to: "fixes"}],
                 %{},
                 inner: :callback,
                 callback: callback,
                 recording_sink: sink
               )

      assert_receive {:recorded, %{event: :ask, node_id: "gate"}}
    end

    test "supports recording_inner module option and native ask_multiple delegates" do
      sink = start_supervised!({Agent, fn -> [] end})

      assert {:ok, ["A", "B"]} =
               Recording.ask_multiple(
                 %Node{id: "gate"},
                 [],
                 %{},
                 recording_inner: AttractorEx.Interviewers.Queue,
                 queue: [["A", "B"]],
                 recording_sink: sink
               )

      events = Agent.get(sink, & &1)
      assert Enum.any?(events, &(&1.event == :ask_multiple))
    end

    test "supports queue alias for ask and callback alias for inform" do
      callback = fn _node, payload, _context -> {:ok, payload[:message]} end

      assert {:ok, "A"} =
               Recording.ask(
                 %Node{id: "gate"},
                 [%{key: "A", label: "Approve", to: "done"}],
                 %{},
                 inner: :queue,
                 queue: ["A"]
               )

      assert {:ok, "done"} =
               Recording.inform(
                 %Node{id: "gate"},
                 %{message: "done"},
                 %{},
                 inner: :callback,
                 callback: callback
               )
    end

    test "returns :ok when the inner interviewer does not implement inform" do
      assert :ok =
               Recording.inform(
                 %Node{id: "gate"},
                 %{message: "noop"},
                 %{},
                 inner: AttractorEx.Node
               )
    end

    test "ignores recording sink failures" do
      bad_sink = fn _event -> raise "boom" end

      assert :ok =
               Recording.inform(
                 %Node{id: "gate"},
                 %{message: "noop"},
                 %{},
                 inner: AttractorEx.Node,
                 recording_sink: bad_sink
               )
    end
  end
end
