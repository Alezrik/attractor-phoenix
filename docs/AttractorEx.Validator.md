# `AttractorEx.Validator`
[🔗](https://github.com/Alezrik/attractor-phoenix/blob/main/lib/attractor_ex/validator.ex#L1)

Validates parsed graphs against the supported Attractor runtime contract.

Validation covers structural errors, routing issues, handler-specific attributes,
human-gate metadata, retry configuration, and model stylesheet linting.

# `start_node_id`

Finds the normalized start node ID for a graph, if present.

# `validate`

Returns all diagnostics for a normalized graph.

# `validate_or_raise`

Validates a graph and raises when error-severity diagnostics are present.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
