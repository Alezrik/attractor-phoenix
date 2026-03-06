defmodule AttractorEx.ConditionTest do
  use ExUnit.Case, async: true

  alias AttractorEx.Condition

  describe "spec: condition expression language" do
    test "evaluates equality and booleans" do
      context = %{"review" => %{"approved" => true, "score" => 10}}

      assert {:ok, true} = Condition.evaluate("review.approved == true", context)
      assert {:ok, true} = Condition.evaluate("review.score == review.score", context)
      assert {:ok, false} = Condition.evaluate("review.score == 0", context)
    end

    test "evaluates numeric comparisons" do
      context = %{"metrics" => %{"coverage" => 92}}

      assert {:ok, true} = Condition.evaluate("metrics.coverage >= 90", context)
      assert {:ok, true} = Condition.evaluate("metrics.coverage > 80", context)
      assert {:ok, false} = Condition.evaluate("metrics.coverage < 60", context)
    end

    test "supports clause chaining with &&" do
      context = %{"build" => %{"ok" => true}, "metrics" => %{"coverage" => 91}}

      assert {:ok, true} =
               Condition.evaluate("build.ok == true && metrics.coverage >= 90", context)

      assert {:ok, false} =
               Condition.evaluate("build.ok == true && metrics.coverage >= 95", context)
    end

    test "nil expression defaults to true" do
      assert {:ok, true} = Condition.evaluate(nil, %{})
    end

    test "supports inequality, less-than-or-equal, and nil literals" do
      context = %{"attempts" => 2, "result" => nil}

      assert {:ok, true} = Condition.evaluate("attempts != 3", context)
      assert {:ok, true} = Condition.evaluate("attempts <= 2", context)
      assert {:ok, true} = Condition.evaluate("result == nil", context)
    end

    test "supports float literal comparisons and string literals" do
      context = %{"metrics" => %{"ratio" => 0.55}, "stage" => %{"name" => "build"}}

      assert {:ok, true} = Condition.evaluate("metrics.ratio >= 0.50", context)
      assert {:ok, true} = Condition.evaluate("stage.name == \"build\"", context)
      assert {:ok, false} = Condition.evaluate("stage.name == \"deploy\"", context)
    end

    test "treats bare clause lookup as truthy/falsey and supports atom keys" do
      context = %{"count" => 0, build: %{ok: true}}

      assert {:ok, true} = Condition.evaluate("build.ok", context)
      assert {:ok, false} = Condition.evaluate("count", context)
    end

    test "valid? returns boolean for parsed expressions" do
      assert Condition.valid?("foo == 1")
      assert_raise FunctionClauseError, fn -> Condition.valid?(123) end
    end
  end
end
