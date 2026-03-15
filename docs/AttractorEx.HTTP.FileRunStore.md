# `AttractorEx.HTTP.FileRunStore`
[🔗](https://github.com/Alezrik/attractor-phoenix/blob/main/lib/attractor_ex/http/file_run_store.ex#L1)

File-backed durable runtime store for HTTP-managed pipeline runs.

Each run is persisted under its own directory with:

- `run.json` for typed run metadata
- `events.ndjson` for append-only event history
- `questions.json` for pending question metadata

---

*Consult [api-reference.md](api-reference.md) for complete listing*
