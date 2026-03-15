# 07. Premium Features And Leadership Criteria

This document captures the features and standards that should make `attractor-phoenix` obviously stronger than the focused reference set.

Primary inspiration:

1. `attractor` for operator-product ambition
2. `kilroy` for depth of operational runtime thinking
3. the overall focused reference set for where the current ceiling appears to be

## Premium Feature Targets

These features should only be built after runtime durability and debugger foundations are in place.

### Planned Premium Features

1. Breakpoints and pause-on-stage debugging
2. Step-through execution mode
3. Stage heatmaps and graph overlays
4. Artifact and run search
5. Saved debugger views
6. Shareable run links
7. Operator annotations on runs and events
8. Pipeline quality scoring and readiness checks before execution

## Definition Of Done For Leadership Position

`attractor-phoenix` should consider itself ahead of the comparison set only when all of the following are true:

1. Runs, events, checkpoints, and question state survive process restarts.
2. Resume and replay behavior are proven by focused regression tests.
3. The main dashboard and run views are subscription-driven, not primarily poll-driven.
4. The builder uses the canonical Elixir parser and validator model.
5. A dedicated debugger exists with timeline, diffs, artifacts, and replay controls.
6. Public docs include a benchmark or conformance scoreboard tied to executable tests.
7. The unified LLM and coding-agent surfaces materially reduce current partial and not-implemented areas.
8. The overall UX is clearly more useful for operators than the best dashboard-oriented reference.

## Suggested Execution Order

The practical implementation order should be:

1. Runtime persistence and typed run state
2. Replay-aware transport and live operator views
3. Debugger MVP
4. Builder canonicalization
5. Conformance harness and published scoreboard
6. Unified LLM and coding-agent completion
7. Premium features such as breakpoints and step-through debugging

## Risks

1. Adding more UI without fixing the runtime model underneath it
2. Keeping multiple incompatible graph interpretations between JS and Elixir
3. Chasing obscure parser parity before operational depth
4. Over-claiming completeness without benchmark-grade conformance evidence
5. Adding premium features that are hard to trust because persistence and replay are weak

## Anti-Goals

This plan does not recommend:

1. turning the project into a generic workflow product unrelated to Attractor semantics
2. prioritizing cosmetic redesign over runtime depth
3. hiding partial areas instead of documenting them
4. adding speculative AI features before the unified-LLM foundation is stronger

## Immediate Next Steps

The next concrete planning layer after this document should be to create implementation epics or issue-sized work items under the same numbering family, for example:

1. `02A` persistent run store
2. `03A` debugger MVP timeline
3. `04A` canonical parser-backed builder API
4. `05A` black-box conformance fixture harness
