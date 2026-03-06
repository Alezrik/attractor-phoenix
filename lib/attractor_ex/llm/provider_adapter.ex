defmodule AttractorEx.LLM.ProviderAdapter do
  @moduledoc false

  alias AttractorEx.LLM.{Request, Response}

  @callback complete(Request.t()) :: Response.t() | {:error, term()}
end
