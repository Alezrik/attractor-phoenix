# `AttractorEx.Handlers.Tool`
[🔗](https://github.com/Alezrik/attractor-phoenix/blob/main/lib/attractor_ex/handlers/tool.ex#L1)

Handler for shell-command tool nodes.

The handler runs the configured command on the local host, captures stdout and stderr,
and optionally executes pre- and post-hook commands declared at graph level.

# `execute`

Executes a tool node and returns the command output in context updates.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
