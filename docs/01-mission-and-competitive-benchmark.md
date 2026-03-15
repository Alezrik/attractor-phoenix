# 01. Mission And Competitive Benchmark

This document defines the benchmark contract used to judge whether `attractor-phoenix` is actually ahead of the strongest reference implementations.

Primary inspiration source:

- `../examples/FOCUSED-RESEARCH.md`

## Mission

`attractor-phoenix` should become the strongest overall implementation in the reference set across three dimensions at the same time:

1. Runtime capability
2. Conformance and implementation rigor
3. Operator experience and premium product features

The target is not merely a broader feature list. The target is a system that combines:

1. durable execution and resume semantics
2. stronger black-box proof of behavior
3. a first-class debugger and operator control plane
4. a cohesive Attractor + coding-agent + unified-LLM story

## Competitive Claim

The project should only claim leadership when all of the following are true at the same time:

1. Runtime depth is stronger than the best runtime-focused reference.
2. Conformance evidence quality is stronger than the best conformance-focused reference.
3. Operator experience is stronger than the best dashboard-focused reference.
4. Public documentation accurately states both strengths and known gaps.

## Reference Set

The focused research document identifies seven primary comparison points:

1. `samueljklee-attractor`
2. `TheFellow-fkyeah`
3. `kilroy`
4. `brynary-attractor`
5. `smartcomputer-ai-forge`
6. `attractor`
7. `aliciapaz-attractor-rb`

## Benchmark Standard

To claim leadership, `attractor-phoenix` should exceed the current set in the following way:

1. Match or exceed `samueljklee-attractor` on execution and server surface.
2. Match or exceed `TheFellow-fkyeah` on conformance evidence quality.
3. Match or exceed `kilroy` on durable run state and resume fidelity.
4. Match or exceed `brynary-attractor` on integration coherence across runtime, agent loop, and unified-LLM abstractions.
5. Match or exceed `attractor` on dashboard and operator usability.
6. Keep explicit honesty like `aliciapaz-attractor-rb` and `smartcomputer-ai-forge` around what remains incomplete.

## Benchmark Dimensions And Weights

Leadership should be scored as a weighted composite so trade-offs are explicit:

1. Runtime capability and durability: `40%`
2. Conformance and proof quality: `30%`
3. Operator experience and product surface: `20%`
4. Integration coherence across Attractor + coding-agent + unified LLM: `10%`

Each dimension should have:

1. measurable criteria
2. executable evidence
3. explicit gap notes when not complete

## Current Position

The repository already has a strong base:

1. Broad `AttractorEx` parser, validator, engine, handlers, HTTP service, SSE, and resume support.
2. Human-in-the-loop support, coding-agent loop primitives, and unified LLM foundations.
3. Published documentation and maintained compliance matrices.
4. Phoenix LiveView surfaces for dashboard, builder, setup, and pipeline library.

The main gaps are structural:

1. Runtime state is still in-memory in the HTTP manager.
2. The main UI is more inspector than operator console.
3. The builder has its own JavaScript DOT interpretation path.
4. Several unified-LLM and appendix-level spec areas remain partial or not implemented.
5. Conformance evidence is strong, but not yet packaged as a visible black-box benchmark suite against competing implementations.

## Required Evidence For Leadership

The benchmark should treat claims as valid only with reproducible evidence:

1. Runtime: restart-safe persistence and replay tests that pass from a clean boot.
2. Conformance: black-box fixtures and runners with published pass/fail output.
3. Operator surface: live run inspection and debugger workflows demonstrable without internal-only tooling.
4. Integration: end-to-end scenario proving runtime + human gate + agent loop + unified LLM behavior in one reproducible path.

Evidence should be linked in docs and traceable to runnable code or test targets.

## Scoring Rubric

Use a 0-5 score per dimension:

1. `0`: not implemented
2. `1`: partial prototype, not dependable
3. `2`: functional but materially incomplete
4. `3`: production-credible baseline
5. `4`: strong implementation with documented evidence
6. `5`: best-in-set quality with benchmark-grade proof

Composite score formula:

1. `(runtime * 0.40) + (conformance * 0.30) + (operator * 0.20) + (integration * 0.10)`

Minimum bar to claim leadership:

1. Composite score `>= 4.2`
2. No dimension below `4.0`
3. No hidden known-gaps in public docs

## Strategic Priorities

The roadmap should optimize for the following order of importance:

1. Durable runtime and replayable state
2. First-class debugger
3. Canonical builder fidelity
4. Black-box conformance leadership
5. Completion of the LLM and agent-platform story
6. A cohesive operator-grade Phoenix product

## Review Cadence

Benchmark reviews should run at a fixed cadence:

1. Weekly internal score review against the rubric.
2. Milestone-based public docs refresh when a dimension score changes.
3. Pre-release leadership check requiring evidence links for all `>= 4.0` claims.

## Anti-Claim Rules

Do not claim "ahead of the set" if any of the following is true:

1. durability or replay depends on in-memory-only state
2. conformance status is not backed by executable fixtures
3. debugger capabilities exist only as internal diagnostics
4. unified LLM or agent-loop claims are broader than current implemented behavior
