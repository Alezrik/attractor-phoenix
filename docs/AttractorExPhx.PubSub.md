# `AttractorExPhx.PubSub`
[🔗](https://github.com/Alezrik/attractor-phoenix/blob/main/lib/attractor_ex_phx/pub_sub.ex#L1)

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

# `snapshot`

```elixir
@type snapshot() :: map()
```

# `child_spec`

Returns a specification to start this module under a supervisor.

See `Supervisor`.

# `start_link`

Starts the PubSub bridge.

# `subscribe_pipeline`

```elixir
@spec subscribe_pipeline(
  String.t(),
  keyword()
) :: {:ok, snapshot()} | {:error, term()}
```

Subscribes the current process to a pipeline topic and returns its current snapshot.

# `topic`

```elixir
@spec topic(String.t()) :: String.t()
```

Returns the Phoenix PubSub topic name for a pipeline.

# `unsubscribe_pipeline`

```elixir
@spec unsubscribe_pipeline(
  String.t(),
  keyword()
) :: :ok
```

Unsubscribes the current process from a pipeline topic.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
