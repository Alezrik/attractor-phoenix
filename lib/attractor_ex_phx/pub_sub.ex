defmodule AttractorExPhx.PubSub do
  @moduledoc """
  Phoenix PubSub bridge for `AttractorEx` pipeline updates.

  This module gives Phoenix applications a push-oriented integration path on top of
  the HTTP manager:

  - server-side processes and LiveViews can subscribe with `subscribe_pipeline/2`
  - browser clients can consume the same updates through a Phoenix Channel

  Subscriptions are organized by per-pipeline topics. The bridge keeps a single
  manager subscription for each pipeline and republishes updates onto Phoenix
  PubSub as plain Elixir messages:

      {:attractor_ex_event, event_map}

  `subscribe_pipeline/2` returns a snapshot so the caller can render initial state
  immediately before incremental events arrive.
  """

  use GenServer

  alias AttractorEx.HTTP.Manager

  @type snapshot :: map()

  @doc "Starts the PubSub bridge."
  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Subscribes the current process to a pipeline topic and returns its current snapshot.
  """
  @spec subscribe_pipeline(String.t(), keyword()) :: {:ok, snapshot()} | {:error, term()}
  def subscribe_pipeline(pipeline_id, opts \\ []) when is_binary(pipeline_id) do
    pubsub_server = Keyword.get(opts, :pubsub_server, configured_pubsub_server())
    bridge = Keyword.get(opts, :bridge, configured_bridge())

    :ok = Phoenix.PubSub.subscribe(pubsub_server, topic(pipeline_id))

    case GenServer.call(bridge, {:ensure_pipeline_subscription, pipeline_id}, :infinity) do
      {:ok, _snapshot} = ok ->
        ok

      {:error, _reason} = error ->
        :ok = Phoenix.PubSub.unsubscribe(pubsub_server, topic(pipeline_id))
        error
    end
  end

  @doc "Unsubscribes the current process from a pipeline topic."
  @spec unsubscribe_pipeline(String.t(), keyword()) :: :ok
  def unsubscribe_pipeline(pipeline_id, opts \\ []) when is_binary(pipeline_id) do
    pubsub_server = Keyword.get(opts, :pubsub_server, configured_pubsub_server())
    Phoenix.PubSub.unsubscribe(pubsub_server, topic(pipeline_id))
  end

  @doc "Returns the Phoenix PubSub topic name for a pipeline."
  @spec topic(String.t()) :: String.t()
  def topic(pipeline_id) when is_binary(pipeline_id), do: "attractor_ex:pipeline:" <> pipeline_id

  @impl true
  def init(opts) do
    {:ok,
     %{
       manager: Keyword.fetch!(opts, :manager),
       pubsub_server: Keyword.fetch!(opts, :pubsub_server),
       subscribed_pipelines: MapSet.new()
     }}
  end

  @impl true
  def handle_call({:ensure_pipeline_subscription, pipeline_id}, _from, state) do
    with :ok <- maybe_subscribe_manager(state, pipeline_id),
         {:ok, snapshot} <- Manager.snapshot(state.manager, pipeline_id) do
      {:reply, {:ok, snapshot}, remember_subscription(state, pipeline_id)}
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_info({:pipeline_event, event}, state) do
    broadcast_event(state, event)
    {:noreply, state}
  end

  def handle_info(_message, state) do
    {:noreply, state}
  end

  defp maybe_subscribe_manager(
         %{manager: manager, subscribed_pipelines: subscriptions},
         pipeline_id
       ) do
    if MapSet.member?(subscriptions, pipeline_id) do
      :ok
    else
      Manager.subscribe(manager, pipeline_id, self())
    end
  end

  defp remember_subscription(state, pipeline_id) do
    %{state | subscribed_pipelines: MapSet.put(state.subscribed_pipelines, pipeline_id)}
  end

  defp broadcast_event(state, %{"pipeline_id" => pipeline_id} = event) do
    Phoenix.PubSub.broadcast(
      state.pubsub_server,
      topic(pipeline_id),
      {:attractor_ex_event, event}
    )
  end

  defp configured_bridge do
    Application.get_env(
      :attractor_phoenix,
      :attractor_pubsub_bridge,
      AttractorPhoenix.AttractorPubSubBridge
    )
  end

  defp configured_pubsub_server do
    Application.fetch_env!(:attractor_phoenix, AttractorPhoenixWeb.Endpoint)
    |> Keyword.fetch!(:pubsub_server)
  end
end
