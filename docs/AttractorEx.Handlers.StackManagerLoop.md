# `AttractorEx.Handlers.StackManagerLoop`
[🔗](https://github.com/Alezrik/attractor-phoenix/blob/main/lib/attractor_ex/handlers/stack_manager_loop.ex#L1)

Handler for manager-loop nodes that observe and steer a child workflow.

The current implementation focuses on polling, stop conditions, and configurable
observe and steer hooks.

# `execute`

Runs the manager loop until the child succeeds, fails, or a stop condition fires.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
