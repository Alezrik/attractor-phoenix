defmodule AttractorEx.LLM.ProviderAdapter do
  @moduledoc """
  Behaviour implemented by unified LLM provider adapters.

  Adapters translate a normalized `AttractorEx.LLM.Request` into a provider-native API
  call and return a normalized `AttractorEx.LLM.Response` or stream of events.
  """

  alias AttractorEx.LLM.{Request, Response, StreamEvent}

  @callback complete(Request.t()) :: Response.t() | {:error, term()}
  @callback stream(Request.t()) :: Enumerable.t(StreamEvent.t()) | {:error, term()}
  @optional_callbacks stream: 1
end
