defmodule AttractorEx.ModelStylesheetTest do
  use ExUnit.Case, async: true

  alias AttractorEx.ModelStylesheet

  describe "parse/1" do
    test "supports nil, empty string, and map stylesheet values" do
      assert {:ok, []} = ModelStylesheet.parse(nil)
      assert {:ok, []} = ModelStylesheet.parse("   ")
      assert {:ok, rules} = ModelStylesheet.parse(%{"node" => %{"reasoning_effort" => "low"}})
      assert is_list(rules)
      assert length(rules) == 1
    end

    test "accepts list stylesheet input with atom keys" do
      stylesheet = [
        %{selector: "#review", attrs: %{reasoning_effort: "high"}},
        %{selector: " ", attrs: %{llm_model: "ignored"}},
        %{selector: ".critical", attrs: %{"temperature" => 0.1}}
      ]

      assert {:ok, rules} = ModelStylesheet.parse(stylesheet)
      assert length(rules) == 2
      assert Enum.any?(rules, &(&1.selector == "#review"))
      assert Enum.any?(rules, &(&1.selector == ".critical"))
    end

    test "parses JSON object and JSON array stylesheets" do
      object_json = ~s({"node":{"llm_provider":"openai"}})

      array_json =
        ~s([{"selector":"type=codergen","attrs":{"llm_model":"gpt-4o-mini"}},{"selector":"#review","attrs":{"reasoning_effort":"high"}}])

      assert {:ok, object_rules} = ModelStylesheet.parse(object_json)
      assert {:ok, array_rules} = ModelStylesheet.parse(array_json)
      assert length(object_rules) == 1
      assert length(array_rules) == 2
    end

    test "rejects invalid stylesheet values" do
      assert {:error, _} = ModelStylesheet.parse(123)
      assert {:error, _} = ModelStylesheet.parse("not-json")
      assert {:error, _} = ModelStylesheet.parse(~s("plain-string"))
    end

    test "ignores malformed array entries and empty selectors" do
      json =
        ~s([{"selector":"#review","attrs":{"reasoning_effort":"high"}},{"selector":"","attrs":{"llm_model":"x"}},{"selector":"node"},42,{"attrs":{"llm_model":"x"}}])

      assert {:ok, rules} = ModelStylesheet.parse(json)
      assert length(rules) == 1
      assert Enum.at(rules, 0).selector == "#review"
    end

    test "filters invalid map rules where attrs are not maps" do
      assert {:ok, rules} = ModelStylesheet.parse(%{"node" => "bad"})
      assert rules == []
    end

    test "expands comma-separated selector list into multiple rules" do
      assert {:ok, rules} =
               ModelStylesheet.parse(%{
                 "node.critical, node[type=tool], #review" => %{"temperature" => 0.2}
               })

      assert length(rules) == 3
      selectors = Enum.map(rules, & &1.selector)
      assert "node.critical" in selectors
      assert "node[type=tool]" in selectors
      assert "#review" in selectors
    end
  end

  describe "attrs_for_node/3" do
    test "applies selectors with precedence: global < type < class < id" do
      {:ok, rules} =
        ModelStylesheet.parse(
          ~s({"node":{"reasoning_effort":"low","llm_provider":"openai"},"type=codergen":{"llm_model":"gpt-4o-mini"},".critical":{"reasoning_effort":"medium"},"#review":{"reasoning_effort":"high"}})
        )

      review =
        ModelStylesheet.attrs_for_node(rules, "review", %{"shape" => "box", "class" => "critical"})

      other =
        ModelStylesheet.attrs_for_node(rules, "other", %{"shape" => "box", "class" => "critical"})

      plain = ModelStylesheet.attrs_for_node(rules, "plain", %{"shape" => "box"})

      assert review["reasoning_effort"] == "high"
      assert other["reasoning_effort"] == "medium"
      assert plain["reasoning_effort"] == "low"
      assert plain["llm_provider"] == "openai"
      assert plain["llm_model"] == "gpt-4o-mini"
    end

    test "supports node[*], node.class, and node[type=...] selectors" do
      {:ok, rules} =
        ModelStylesheet.parse(
          ~s({"node[*]":{"temperature":0.7},"node.critical":{"reasoning_effort":"high"},"node[type=tool]":{"timeout":"90s"}})
        )

      tool =
        ModelStylesheet.attrs_for_node(
          rules,
          "ship",
          %{"type" => "tool", "shape" => "parallelogram", "class" => "critical"}
        )

      codergen =
        ModelStylesheet.attrs_for_node(
          rules,
          "plan",
          %{"shape" => "box", "class" => "critical,planning"}
        )

      assert tool["temperature"] == 0.7
      assert tool["reasoning_effort"] == "high"
      assert tool["timeout"] == "90s"
      assert codergen["temperature"] == 0.7
      assert codergen["reasoning_effort"] == "high"
      refute Map.has_key?(codergen, "timeout")
    end

    test "supports star selector and ignores unknown selectors" do
      {:ok, rules} =
        ModelStylesheet.parse(
          ~s({"*":{"llm_provider":"openai"},"unknown.selector":{"reasoning_effort":"high"}})
        )

      attrs = ModelStylesheet.attrs_for_node(rules, "task", %{"shape" => "box"})
      assert attrs["llm_provider"] == "openai"
      refute Map.has_key?(attrs, "reasoning_effort")
    end

    test "supports compound selectors and specificity within same rule family" do
      {:ok, rules} =
        ModelStylesheet.parse(
          ~s({"node[type=\\"codergen\\"].critical":{"llm_model":"gpt-4.1-mini"},"node.critical":{"reasoning_effort":"medium"},"#review.critical":{"reasoning_effort":"high"},"node#review":{"temperature":0.1}})
        )

      review =
        ModelStylesheet.attrs_for_node(
          rules,
          "review",
          %{"type" => "codergen", "shape" => "box", "class" => "critical ops"}
        )

      plain_critical =
        ModelStylesheet.attrs_for_node(
          rules,
          "plan",
          %{"type" => "codergen", "shape" => "box", "class" => "critical"}
        )

      assert review["llm_model"] == "gpt-4.1-mini"
      assert review["reasoning_effort"] == "high"
      assert review["temperature"] == 0.1

      assert plain_critical["llm_model"] == "gpt-4.1-mini"
      assert plain_critical["reasoning_effort"] == "medium"
      refute Map.has_key?(plain_critical, "temperature")
    end
  end
end
