defmodule AttractorEx.HTTP do
  @moduledoc """
  Convenience entry point for starting and stopping the AttractorEx HTTP service.

  The service is composed of `AttractorEx.HTTP.Manager`, a `Registry`, and a Bandit
  server running `AttractorEx.HTTP.Router`.
  """

  alias AttractorEx.HTTP.{Manager, Router}

  @doc "Starts the HTTP manager, registry, and Bandit server."
  def start_server(opts \\ []) do
    manager_name = Keyword.get(opts, :manager, Manager)
    registry_name = Keyword.get(opts, :registry, Module.concat(manager_name, Registry))

    manager_opts =
      opts
      |> Keyword.take([:store, :store_root])
      |> Keyword.put(:name, manager_name)

    with {:ok, _pid} <- ensure_genserver_started(Manager, manager_opts),
         {:ok, _pid} <- ensure_registry_started(keys: :duplicate, name: registry_name) do
      bandit_opts = [
        plug: {Router, manager: manager_name, registry: registry_name},
        scheme: :http,
        port: Keyword.get(opts, :port, 0),
        ip: Keyword.get(opts, :ip, {127, 0, 0, 1})
      ]

      Bandit.start_link(bandit_opts)
    end
  end

  @doc "Stops a running HTTP server process or named server."
  def stop_server(server) when is_pid(server) do
    GenServer.stop(server)
    :ok
  end

  def stop_server(server) when is_atom(server) do
    GenServer.stop(server)
    :ok
  end

  defp ensure_genserver_started(module, opts) do
    case GenServer.start_link(module, opts, name: Keyword.get(opts, :name)) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
      other -> other
    end
  end

  defp ensure_registry_started(opts) do
    case Registry.start_link(opts) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
      other -> other
    end
  end
end
