# `AttractorEx.LLM.Client`
[🔗](https://github.com/Alezrik/attractor-phoenix/blob/main/lib/attractor_ex/llm/client.ex#L1)

Provider-agnostic LLM client used by codergen nodes and agent sessions.

The client resolves providers, applies middleware, delegates to adapter modules, and
supports both request/response and streaming flows.

# `middleware`

```elixir
@type middleware() ::
  (AttractorEx.LLM.Request.t(), (AttractorEx.LLM.Request.t() -&gt; any()) -&gt; any())
```

# `t`

```elixir
@type t() :: %AttractorEx.LLM.Client{
  default_provider: String.t() | nil,
  middleware: [middleware()],
  providers: %{optional(String.t()) =&gt; module()},
  streaming_middleware: [middleware()]
}
```

# `complete`

Executes a completion request and returns either a response or an error tuple.

# `complete_with_request`

Executes a completion request and also returns the resolved request.

# `stream`

Executes a streaming request and returns the event stream or an error tuple.

# `stream_with_request`

Executes a streaming request and also returns the resolved request.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
