# Spec Alignment

`AttractorEx` is built against the strongDM Attractor family of specifications, but it does not claim full parity with every upstream feature.

## Upstream Sources

- [Attractor specification](https://github.com/strongdm/attractor/blob/main/attractor-spec.md)
- [Coding-agent loop specification](https://github.com/strongdm/attractor/blob/main/coding-agent-loop-spec.md)
- [Unified LLM specification](https://github.com/strongdm/attractor/blob/main/unified-llm-spec.md)

## Local Reference Documents

This repository keeps implementation-facing compliance reports under `lib/attractor_ex/`:

- `ATTRACTOR_SPEC_COMPLIANCE.md`
- `CODING_AGENT_LOOP_COMPLIANCE.md`
- `UNIFIED_LLM_SPEC_COMPLIANCE.md`

Those documents are included in the generated ExDoc output so the rendered docs expose both:

- narrative architecture guides
- section-by-section compliance detail

## What To Expect

The highest-confidence parts of the implementation today are:

- parser and validation coverage for the supported DOT subset
- node execution and routing
- human-in-the-loop flows
- HTTP service mode
- the low-level unified LLM client contract

Areas explicitly documented as partial or not implemented remain partial or not implemented in the generated docs. The goal of this documentation set is to be accurate first, then polished.
