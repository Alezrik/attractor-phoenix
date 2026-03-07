defmodule AttractorExTest.ValidatorRule do
  @moduledoc false

  def validate(_graph) do
    %{severity: :warning, code: :custom_module_rule, message: "module rule", node_id: "done"}
  end
end
