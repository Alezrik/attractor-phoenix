# `AttractorEx.LLM.Error`
[🔗](https://github.com/Alezrik/attractor-phoenix/blob/main/lib/attractor_ex/llm/error.ex#L1)

Typed error returned by unified LLM adapters and client retries.

The struct normalizes provider/API/transport failures into a consistent shape so
callers can make retry, logging, and host-event decisions without pattern matching
on provider-specific payloads.

# `error_type`

```elixir
@type error_type() ::
  :transport
  | :timeout
  | :rate_limited
  | :authentication
  | :permission
  | :invalid_request
  | :server
  | :api
  | :unsupported
  | :unknown
```

# `t`

```elixir
@type t() :: %AttractorEx.LLM.Error{
  __exception__: true,
  code: String.t() | nil,
  details: map(),
  message: String.t(),
  provider: String.t() | nil,
  raw: term(),
  retry_after_ms: non_neg_integer() | nil,
  retryable: boolean(),
  status: pos_integer() | nil,
  type: error_type()
}
```

# `from_http_response`

```elixir
@spec from_http_response(String.t() | nil, pos_integer(), term(), map()) :: t()
```

# `new`

```elixir
@spec new(keyword()) :: t()
```

# `normalize`

```elixir
@spec normalize(
  term(),
  keyword()
) :: t()
```

# `retryable?`

```elixir
@spec retryable?(term()) :: boolean()
```

# `transport`

```elixir
@spec transport(String.t() | nil, term()) :: t()
```

---

*Consult [api-reference.md](api-reference.md) for complete listing*
