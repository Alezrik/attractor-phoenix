defmodule AttractorEx.HumanGatePropertyTest do
  use ExUnit.Case, async: true
  use PropCheck, default_opts: [numtests: 100]

  import AttractorEx.TestGenerators

  alias AttractorEx.{Edge, Graph, HumanGate}

  property "choices_for returns one choice per outgoing edge and preserves label fallbacks" do
    forall count <- integer(1, 8) do
      outgoing_edges =
        Enum.map(1..count, fn index ->
          attrs =
            if rem(index, 2) == 0 do
              %{"label" => ""}
            else
              %{"label" => "Choice #{index}"}
            end

          Edge.new("review", "step#{index}", attrs)
        end)

      graph = %Graph{edges: outgoing_edges ++ [Edge.new("other", "ignored", %{})]}
      choices = HumanGate.choices_for("review", graph)

      assert length(choices) == count
      assert Enum.map(choices, & &1.to) == Enum.map(1..count, &"step#{&1}")

      assert Enum.map(choices, & &1.label) ==
               Enum.map(1..count, fn index ->
                 if rem(index, 2) == 0, do: "step#{index}", else: "Choice #{index}"
               end)
    end
  end

  property "match_choice is case-insensitive and trims surrounding whitespace" do
    forall destination <- nonempty_identifier() do
      choice = %{key: "X", label: "Review #{destination}", to: destination}

      assert HumanGate.match_choice("  #{String.upcase(destination)}  ", [choice]) == choice
    end
  end

  property "choices_for derives accelerator keys from bracketed labels" do
    forall codepoint <- integer(?a, ?z) do
      label = "[#{<<codepoint>>}] Continue"
      graph = %Graph{edges: [Edge.new("review", "done", %{"label" => label})]}

      assert [%{key: key}] = HumanGate.choices_for("review", graph)
      assert key == String.upcase(<<codepoint>>)
    end
  end
end
