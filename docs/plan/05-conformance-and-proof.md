# 05. Conformance And Proof

This workstream exists to make the project's claims provable, not just plausible.

Primary inspiration:

1. `TheFellow-fkyeah` for black-box conformance discipline
2. `smartcomputer-ai-forge` for conformance decomposition and gap-management rigor
3. `aliciapaz-attractor-rb` for readable divergence tracking

## Goal

Build a benchmark-grade black-box conformance suite and publish a visible scoreboard tied to executable evidence.

## Work Items

1. Create scenario fixtures for parser, validator, runtime, state, HTTP, agent loop, and unified LLM behavior.
2. Build black-box conformance runners inspired by `TheFellow-fkyeah`.
3. Split conformance suites by domain:
   - parsing
   - runtime
   - state
   - transport
   - agent loop
   - unified LLM
4. Publish a maintained scoreboard in docs.
5. Track exact gaps explicitly and link each to tests or roadmap items.

## Deliverables

1. Black-box conformance suite
2. Public benchmark matrix
3. Explicit gap ledger
4. Docs that tie status claims to test evidence

## Success Criteria

This workstream is done when:

1. implementation claims can be traced to executable tests
2. the repo exposes a public benchmark or conformance scorecard
3. partial or missing areas are documented explicitly, not implied away
4. the proof quality is at least as strong as the best conformance-first reference
