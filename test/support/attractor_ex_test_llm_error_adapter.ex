defmodule AttractorExTest.LLMErrorAdapter do
  @moduledoc false

  def complete(_request), do: {:error, :upstream_error}
end
