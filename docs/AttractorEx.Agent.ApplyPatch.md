# `AttractorEx.Agent.ApplyPatch`
[🔗](https://github.com/Alezrik/attractor-phoenix/blob/main/lib/attractor_ex/agent/apply_patch.ex#L1)

Applies `apply_patch` v4a-style filesystem updates against a local execution environment.

The implementation is intentionally conservative. It supports add, delete, update,
and move operations using the appendix-style patch envelope and verifies update hunks
against current file contents before writing changes.

# `operation_result`

```elixir
@type operation_result() :: %{operation: String.t(), path: String.t()}
```

# `apply`

```elixir
@spec apply(term(), String.t()) :: {:ok, [operation_result()]} | {:error, String.t()}
```

---

*Consult [api-reference.md](api-reference.md) for complete listing*
