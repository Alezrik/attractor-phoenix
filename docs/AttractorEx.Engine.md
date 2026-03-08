# `AttractorEx.Engine`
[🔗](https://github.com/Alezrik/attractor-phoenix/blob/main/lib/attractor_ex/engine.ex#L1)

Core execution engine for AttractorEx pipelines.

This module owns graph transformation, validation, handler dispatch, checkpointing,
runtime event emission, retry logic, goal-gate enforcement, and edge selection.

# `resume`

Resumes execution from a checkpoint file, map, or `AttractorEx.Checkpoint`.

# `run`

Parses, validates, and executes a DOT pipeline.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
