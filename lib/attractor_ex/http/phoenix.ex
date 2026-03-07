defmodule AttractorEx.HTTP.Phoenix do
  @moduledoc """
  Optional Phoenix integration helpers for the AttractorEx HTTP API.

  This keeps the standalone Bandit server path intact while making it easy to:

  1. Start the AttractorEx HTTP manager/registry under your Phoenix supervision tree.
  2. Forward a Phoenix router scope to `AttractorEx.HTTP.Router`.

  Example child setup:

      children = [
        ...,
        AttractorEx.HTTP.Phoenix.child_spec(name: MyApp.AttractorHTTP)
      ]

  Example router setup:

      forward "/attractor",
        AttractorEx.HTTP.Router,
        AttractorEx.HTTP.Phoenix.router_opts(name: MyApp.AttractorHTTP)
  """

  alias AttractorEx.HTTP.Manager

  def child_spec(opts \\ []) do
    %{
      id: Keyword.get(opts, :name, __MODULE__),
      start: {__MODULE__, :start_link, [opts]}
    }
  end

  def start_link(opts \\ []) do
    manager = manager_name(opts)
    registry = registry_name(opts, manager)

    children = [
      {Manager, name: manager},
      {Registry, keys: :duplicate, name: registry}
    ]

    Supervisor.start_link(children,
      strategy: :one_for_one,
      name: supervisor_name(opts)
    )
  end

  def router_opts(opts \\ []) do
    manager = manager_name(opts)
    registry = registry_name(opts, manager)
    [manager: manager, registry: registry]
  end

  defp manager_name(opts) do
    cond do
      Keyword.has_key?(opts, :manager) ->
        Keyword.fetch!(opts, :manager)

      Keyword.has_key?(opts, :name) ->
        Module.concat(Keyword.fetch!(opts, :name), Manager)

      true ->
        Manager
    end
  end

  defp registry_name(opts, manager) do
    Keyword.get(opts, :registry, Module.concat(manager, Registry))
  end

  defp supervisor_name(opts) do
    cond do
      Keyword.has_key?(opts, :supervisor) ->
        Keyword.fetch!(opts, :supervisor)

      Keyword.has_key?(opts, :name) ->
        Module.concat(Keyword.fetch!(opts, :name), Supervisor)

      true ->
        __MODULE__.Supervisor
    end
  end
end
