# `AttractorEx.Handlers.Codergen`
[🔗](https://github.com/Alezrik/attractor-phoenix/blob/main/lib/attractor_ex/handlers/codergen.ex#L1)

Handler for LLM-driven `codergen` stages.

Codergen nodes derive their prompt from `prompt` or `label`, write prompt and
response artifacts, and can run through either the unified LLM client layer or a
legacy backend module.

# `execute`

Executes a codergen node and returns an `AttractorEx.Outcome`.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
