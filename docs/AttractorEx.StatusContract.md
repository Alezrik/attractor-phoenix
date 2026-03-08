# `AttractorEx.StatusContract`
[🔗](https://github.com/Alezrik/attractor-phoenix/blob/main/lib/attractor_ex/status_contract.ex#L1)

Serializes handler outcomes into the `status.json` artifact contract.

The payload shape is aligned with the Appendix C-style status fields used by the
upstream Attractor documentation while preserving a few backward-compatible aliases.

# `serialize_outcome`

Builds a normalized runtime map representation of an outcome.

# `status_file_payload`

Builds the on-disk status-file payload for an outcome.

# `write_status_file`

Writes a pretty-printed `status.json` payload to disk.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
