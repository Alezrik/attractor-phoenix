# `AttractorEx.Checkpoint`
[🔗](https://github.com/Alezrik/attractor-phoenix/blob/main/lib/attractor_ex/checkpoint.ex#L1)

Serializable checkpoint snapshot for resumable pipeline execution.

The engine writes checkpoints after every stage and accepts them again through
`AttractorEx.resume/3`.

# `new`

Builds a checkpoint using the current UTC timestamp.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
