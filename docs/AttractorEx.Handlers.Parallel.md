# `AttractorEx.Handlers.Parallel`
[🔗](https://github.com/Alezrik/attractor-phoenix/blob/main/lib/attractor_ex/handlers/parallel.ex#L1)

Handler for parallel branch fan-out nodes.

It executes each outgoing branch through a configurable branch runner and aggregates
the branch results according to the configured join policy.

# `execute`

Executes all parallel branches and aggregates their outcomes.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
