defmodule AttractorPhoenix.AttractorHTTPServer do
  @moduledoc false

  def child_spec(opts) do
    %{
      id: Keyword.get(opts, :name, __MODULE__),
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent,
      shutdown: 5_000
    }
  end

  def start_link(opts) do
    AttractorEx.start_http_server(opts)
  end
end
