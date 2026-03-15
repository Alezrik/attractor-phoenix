# `AttractorEx.Authoring`
[🔗](https://github.com/Alezrik/attractor-phoenix/blob/main/lib/attractor_ex/authoring.ex#L1)

Canonical authoring helpers for DOT-backed builder workflows.

This module keeps authoring fidelity aligned with the runtime by routing parsing,
validation, formatting, templates, and autofix suggestions through the same
normalized `AttractorEx.Graph` model used by execution.

# `analyze`

Returns the canonical authoring analysis for a DOT document.

# `format`

Returns the stable canonical DOT format for the given graph.

# `templates`

Returns available builder templates.

# `transform`

Applies a supported authoring transform and returns canonical output.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
