defmodule AttractorEx.ConditionPropertyTest do
  use ExUnit.Case, async: true
  use PropCheck, default_opts: [numtests: 100]

  import AttractorEx.TestGenerators

  alias AttractorEx.Condition

  property "integer literals round-trip through nested equality comparisons" do
    forall [outer_key, inner_key, value] <- [
             nonempty_identifier(),
             nonempty_identifier(),
             integer()
           ] do
      context = %{outer_key => %{inner_key => value}}

      Condition.evaluate("#{outer_key}.#{inner_key} == #{value}", context) == {:ok, true}
    end
  end

  property "string literals round-trip through equality comparisons" do
    forall value <- nonempty_identifier() do
      Condition.evaluate(~s(value == "#{value}"), %{"value" => value}) == {:ok, true}
    end
  end

  property "bare clauses treat zero as false and non-zero integers as true" do
    forall value <- integer() do
      expected = value != 0

      Condition.evaluate("value", %{"value" => value}) == {:ok, expected}
    end
  end

  property "boolean clause chains behave like logical and" do
    forall [a, b, c] <- [boolean(), boolean(), boolean()] do
      expected = a and b and c

      Condition.evaluate("a && b && c", %{"a" => a, "b" => b, "c" => c}) == {:ok, expected}
    end
  end
end
