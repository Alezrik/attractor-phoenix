# `AttractorEx.HTTP.Manager`
[🔗](https://github.com/Alezrik/attractor-phoenix/blob/main/lib/attractor_ex/http/manager.ex#L1)

GenServer that owns durable runtime state for HTTP-managed pipeline runs.

Run metadata, event history, checkpoints, pending questions, and artifact indexes are
persisted through a pluggable run store so HTTP and Phoenix consumers can replay run
history after process restarts.

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

# `replay_events`

Returns persisted events after the given sequence number.

# `snapshot`

# `start_link`

Starts the HTTP pipeline manager.

# `submit_answer`

# `subscribe`

# `timeout_question`

---

*Consult [api-reference.md](api-reference.md) for complete listing*
