defmodule AttractorEx.NodeOutcomeTest do
  use ExUnit.Case, async: true

  alias AttractorEx.{Node, Outcome}

  describe "node defaults and shape mapping" do
    test "defaults shape/type and normalizes booleans + retry targets" do
      node =
        Node.new("task", %{
          "shape" => " box ",
          "goal_gate" => "yes",
          "retry_target" => " recover ",
          "fallback_retry_target" => " "
        })

      assert node.shape == "box"
      assert node.type == "codergen"
      assert node.goal_gate == true
      assert node.retry_target == "recover"
      assert node.fallback_retry_target == nil
    end

    test "maps known shapes and falls back to codergen for unknown shape" do
      assert Node.handler_type_for_shape("parallelogram") == "tool"
      assert Node.handler_type_for_shape("unknown") == "codergen"
      assert Node.handler_type_for_shape(nil) == "codergen"
    end
  end

  describe "outcome constructors" do
    test "success/partial/fail/retry constructors set expected fields" do
      assert %Outcome{status: :success, context_updates: %{"k" => "v"}} =
               Outcome.success(%{"k" => "v"})

      assert %Outcome{status: :partial_success} = Outcome.partial_success()
      assert %Outcome{status: :fail, failure_reason: "boom"} = Outcome.fail("boom")
      assert %Outcome{status: :retry, failure_reason: "again"} = Outcome.retry("again")
    end
  end
end
