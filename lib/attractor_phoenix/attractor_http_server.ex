defmodule AttractorPhoenix.AttractorHTTPServer do
  @moduledoc false

  defdelegate child_spec(opts), to: AttractorExPhx.HTTPServer
  defdelegate start_link(opts), to: AttractorExPhx.HTTPServer
end
