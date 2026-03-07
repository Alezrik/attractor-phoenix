defmodule AttractorPhoenix.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    attractor_http_opts = Application.fetch_env!(:attractor_phoenix, :attractor_http)

    children = [
      AttractorPhoenixWeb.Telemetry,
      {DNSCluster, query: Application.get_env(:attractor_phoenix, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: AttractorPhoenix.PubSub},
      {AttractorPhoenix.AttractorHTTPServer,
       port: Keyword.fetch!(attractor_http_opts, :port),
       ip: Keyword.fetch!(attractor_http_opts, :ip),
       manager: AttractorPhoenix.AttractorHTTP.Manager,
       registry: AttractorPhoenix.AttractorHTTP.Registry,
       name: AttractorPhoenix.AttractorHTTPServer},
      # Start a worker by calling: AttractorPhoenix.Worker.start_link(arg)
      # {AttractorPhoenix.Worker, arg},
      # Start to serve requests, typically the last entry
      AttractorPhoenixWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: AttractorPhoenix.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    AttractorPhoenixWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
