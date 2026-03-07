defmodule AttractorEx.InterviewersTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  alias AttractorEx.Interviewers.{AutoApprove, Callback, Console, Queue}
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
  end
end
