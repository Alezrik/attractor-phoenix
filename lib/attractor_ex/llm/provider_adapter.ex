defmodule AttractorEx.LLM.ProviderAdapter do
  @moduledoc false

  alias AttractorEx.LLM.{Request, Response, StreamEvent}

  @callback complete(Request.t()) :: Response.t() | {:error, term()}
  @callback stream(Request.t()) :: Enumerable.t(StreamEvent.t()) | {:error, term()}
  @optional_callbacks stream: 1
end
