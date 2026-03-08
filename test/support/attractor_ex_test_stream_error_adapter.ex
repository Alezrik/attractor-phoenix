defmodule AttractorExTest.StreamErrorAdapter do
  @moduledoc false

  alias AttractorEx.LLM.Request

  def complete(%Request{}), do: {:error, :unused}
  def stream(%Request{}), do: {:error, :stream_boom}
end
