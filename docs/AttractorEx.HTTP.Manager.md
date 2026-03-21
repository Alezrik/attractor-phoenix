# `AttractorEx.HTTP.Manager`
[🔗](https://github.com/Alezrik/attractor-phoenix/blob/main/lib/attractor_ex/http/manager.ex#L1)

GenServer that owns durable runtime state for HTTP-managed pipeline runs.

Run metadata, event history, checkpoints, pending questions, and artifact indexes are
persisted through a pluggable run store so HTTP and Phoenix consumers can replay run
history after process restarts. The manager also admits one explicit
checkpoint-backed resume for cancelled runs after the human gate has been fully
cleared and the accepted answer has been durably recorded.

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

# `pipeline_status_payload`

# `record_event`

# `register_question`

# `replay_events`

Returns persisted events after the given sequence number.

# `reset`

Clears in-memory and persisted HTTP runtime state for the current manager.

# `resume_pipeline`

Attempts one explicit checkpoint-backed resume for an admitted interrupted run.

# `snapshot`

# `start_link`

Starts the HTTP pipeline manager.

# `submit_answer`

# `subscribe`

# `timeout_question`

---

*Consult [api-reference.md](api-reference.md) for complete listing*
