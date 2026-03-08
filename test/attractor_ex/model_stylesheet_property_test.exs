defmodule AttractorEx.ModelStylesheetPropertyTest do
  use ExUnit.Case, async: true
  use PropCheck, default_opts: [numtests: 100]

  import AttractorEx.TestGenerators

  alias AttractorEx.ModelStylesheet

  property "wildcard map stylesheets apply to any node" do
    forall [provider, model, timeout_seconds] <- [
             nonempty_identifier(),
             nonempty_identifier(),
             integer(1, 10_000)
           ] do
      expected_attrs = %{
        "llm_provider" => provider,
        "llm_model" => model,
        "timeout" => "#{timeout_seconds}s"
      }

      stylesheet = %{"*" => Map.put(expected_attrs, :llm_model, model)}

      assert {:ok, rules} = ModelStylesheet.parse(stylesheet)

      assert ModelStylesheet.attrs_for_node(rules, "task", %{
               "type" => "codergen",
               "shape" => "box"
             }) ==
               expected_attrs
    end
  end

  property "selector specificity prefers id over class over wildcard" do
    forall [base_model, class_model, id_model] <- [
             nonempty_identifier(),
             nonempty_identifier(),
             nonempty_identifier()
           ] do
      assert {:ok, rules} =
               ModelStylesheet.parse(%{
                 "*" => %{"llm_model" => base_model},
                 ".critical" => %{"llm_model" => class_model},
                 "#review" => %{"llm_model" => id_model}
               })

      assert ModelStylesheet.attrs_for_node(rules, "review", %{
               "class" => "critical",
               "type" => "codergen"
             })["llm_model"] ==
               id_model

      assert ModelStylesheet.attrs_for_node(rules, "other", %{
               "class" => "critical",
               "type" => "codergen"
             })["llm_model"] ==
               class_model

      assert ModelStylesheet.attrs_for_node(rules, "other", %{"type" => "codergen"})["llm_model"] ==
               base_model
    end
  end
end
