# `AttractorEx.Handlers.WaitForHuman`
[🔗](https://github.com/Alezrik/attractor-phoenix/blob/main/lib/attractor_ex/handlers/wait_for_human.ex#L1)

Handler for `wait.human` nodes.

It collects available choices, resolves an answer from context or an interviewer
adapter, normalizes that answer, and returns routing hints for the engine.

# `execute`

Executes a human-gate node against a graph-aware set of outgoing choices.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
