defmodule AttractorExTest.BadLLMAdapter do
  @moduledoc false

  alias AttractorEx.LLM.Request

  def complete(%Request{}), do: :unexpected
end
