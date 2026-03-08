# `AttractorEx.LLM.Client`
[🔗](https://github.com/Alezrik/attractor-phoenix/blob/main/lib/attractor_ex/llm/client.ex#L1)

Provider-agnostic LLM client used by codergen nodes and agent sessions.

The client resolves providers, applies middleware, delegates to adapter modules, and
supports both request/response and streaming flows.

Beyond the low-level `complete/2` and `stream/2` APIs, the module also exposes:

1. `from_env/1` for runtime construction from application config
2. module-level default-client helpers
3. spec-aligned convenience wrappers such as `generate/2`
4. stream accumulation helpers for callers that want a final normalized response
5. JSON object generation helpers layered on top of the normalized response surface

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

# `accumulate_stream`

```elixir
@spec accumulate_stream(AttractorEx.LLM.Request.t()) ::
  AttractorEx.LLM.Response.t() | {:error, term()}
```

Consumes a raw event stream and returns a normalized final response.

This is useful for callers that want provider streaming for latency but still need a
single accumulated `AttractorEx.LLM.Response`.

# `accumulate_stream`

```elixir
@spec accumulate_stream(t(), AttractorEx.LLM.Request.t()) ::
  AttractorEx.LLM.Response.t() | {:error, term()}
```

Consumes a raw event stream and returns a normalized final response.

# `accumulate_stream_with_request`

```elixir
@spec accumulate_stream_with_request(t(), AttractorEx.LLM.Request.t()) ::
  {:ok, AttractorEx.LLM.Response.t(), AttractorEx.LLM.Request.t()}
  | {:error, term()}
```

Consumes a raw event stream and returns the accumulated response plus resolved request.

# `clear_default`

```elixir
@spec clear_default() :: :ok
```

Clears the module-level default client.

# `complete`

```elixir
@spec complete(AttractorEx.LLM.Request.t()) ::
  AttractorEx.LLM.Response.t() | {:error, term()}
```

Executes a completion request via the configured module-level default client.

# `complete`

Executes a completion request and returns either a response or an error tuple.

# `complete_with_request`

Executes a completion request and also returns the resolved request.

# `default`

```elixir
@spec default() :: t() | nil
```

Returns the configured module-level default client, or `nil`.

# `from_env`

```elixir
@spec from_env(keyword()) :: t()
```

Builds a client from application config, with direct opts taking precedence.

Supported config shape:

    config :attractor_phoenix, :attractor_ex_llm,
      providers: %{"openai" => MyApp.OpenAIAdapter},
      default_provider: "openai"

# `generate`

```elixir
@spec generate(AttractorEx.LLM.Request.t()) ::
  AttractorEx.LLM.Response.t() | {:error, term()}
```

Spec-style completion alias for `complete/2`.

# `generate`

```elixir
@spec generate(t(), AttractorEx.LLM.Request.t()) ::
  AttractorEx.LLM.Response.t() | {:error, term()}
```

Spec-style completion alias for `complete/2`.

# `generate_object`

```elixir
@spec generate_object(AttractorEx.LLM.Request.t()) ::
  {:ok, map() | list()} | {:error, term()}
```

Generates a JSON object via the configured module-level default client.

# `generate_object`

```elixir
@spec generate_object(t(), AttractorEx.LLM.Request.t()) ::
  {:ok, map() | list()} | {:error, term()}
```

Generates a JSON object from a non-streaming response.

The response body is decoded from `response.text`.

# `generate_object_with_request`

```elixir
@spec generate_object_with_request(t(), AttractorEx.LLM.Request.t()) ::
  {:ok, map() | list(), AttractorEx.LLM.Response.t(),
   AttractorEx.LLM.Request.t()}
  | {:error, term()}
```

Generates a JSON object from a non-streaming response and also returns transport data.

# `generate_with_request`

```elixir
@spec generate_with_request(t(), AttractorEx.LLM.Request.t()) ::
  {:ok, AttractorEx.LLM.Response.t(), AttractorEx.LLM.Request.t()}
  | {:error, term()}
```

Spec-style completion alias for `complete_with_request/2`.

# `new`

```elixir
@spec new(keyword()) :: t()
```

Builds a client from keyword options.

# `put_default`

```elixir
@spec put_default(t()) :: t()
```

Stores a module-level default client used by the arity-1 helpers.

# `stream`

```elixir
@spec stream(AttractorEx.LLM.Request.t()) :: Enumerable.t() | {:error, term()}
```

Executes a streaming request via the configured module-level default client.

# `stream`

Executes a streaming request and returns the event stream or an error tuple.

# `stream_object`

```elixir
@spec stream_object(AttractorEx.LLM.Request.t()) ::
  {:ok, map() | list()} | {:error, term()}
```

Generates a JSON object from a streamed response via the default client.

# `stream_object`

```elixir
@spec stream_object(t(), AttractorEx.LLM.Request.t()) ::
  {:ok, map() | list()} | {:error, term()}
```

Generates a JSON object by first accumulating a streamed response.

# `stream_object_with_request`

```elixir
@spec stream_object_with_request(t(), AttractorEx.LLM.Request.t()) ::
  {:ok, map() | list(), AttractorEx.LLM.Response.t(),
   AttractorEx.LLM.Request.t()}
  | {:error, term()}
```

Generates a JSON object by first accumulating a streamed response and also returns
the normalized response plus resolved request.

# `stream_with_request`

Executes a streaming request and also returns the resolved request.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
