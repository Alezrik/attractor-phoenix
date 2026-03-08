# `AttractorEx.Interviewer`
[🔗](https://github.com/Alezrik/attractor-phoenix/blob/main/lib/attractor_ex/interviewer.ex#L1)

Behaviour for human-in-the-loop adapters used by `wait.human`.

Interviewers can source answers from a console, queue, callback, HTTP workflow, or
any custom adapter that implements the callbacks below.

# `ask`

```elixir
@callback ask(AttractorEx.Node.t(), [map()], map(), keyword()) ::
  {:ok, term()} | {:timeout} | {:skip} | {:error, term()} | term() | nil
```

# `ask_multiple`
*optional* 

```elixir
@callback ask_multiple(AttractorEx.Node.t(), [map()], map(), keyword()) ::
  {:ok, [term()]} | {:timeout} | {:skip} | {:error, term()} | term() | nil
```

# `inform`
*optional* 

```elixir
@callback inform(AttractorEx.Node.t(), map(), map(), keyword()) ::
  :ok | {:ok, term()} | {:error, term()} | term()
```

---

*Consult [api-reference.md](api-reference.md) for complete listing*
