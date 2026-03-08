# `AttractorEx.HTTP.Manager`
[🔗](https://github.com/Alezrik/attractor-phoenix/blob/main/lib/attractor_ex/http/manager.ex#L1)

GenServer that owns the in-memory state for HTTP-managed pipeline runs.

It tracks pipeline status, events, checkpoints, pending human questions, and event
subscribers, and acts as the coordination point between the engine and the router.

# `cancel`

# `child_spec`

Returns a specification to start this module under a supervisor.

See `Supervisor`.

# `create_pipeline`

Creates and starts a pipeline run under HTTP management.

# `get_pipeline`

# `list_pipelines`

# `pending_questions`

# `pipeline_checkpoint`

# `pipeline_context`

# `pipeline_events`

# `pipeline_graph`

# `record_event`

# `register_question`

# `start_link`

Starts the HTTP pipeline manager.

# `submit_answer`

# `subscribe`

# `timeout_question`

---

*Consult [api-reference.md](api-reference.md) for complete listing*
