# `AttractorEx.HandlerRegistry`
[🔗](https://github.com/Alezrik/attractor-phoenix/blob/main/lib/attractor_ex/handler_registry.ex#L1)

Resolves node types to executable handler modules.

The registry includes the built-in handlers required by the runtime and supports
dynamic extension through `register/2`.

# `handler_for`

Alias for `resolve/1`.

# `known_type?`

Returns whether a type string is known to the registry.

# `register`

Registers a handler module for an explicit type string.

# `resolve`

Resolves the effective handler module for a node.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
