# 04. Builder And Authoring Fidelity

This workstream removes correctness drift between the UI authoring experience and the actual engine.

Primary inspiration:

1. `samueljklee-attractor` for reducing ambiguity between definition and execution
2. `TheFellow-fkyeah` for keeping semantics testable and explicit

## Goal

Make the visual builder a trustworthy client of the canonical Elixir parser and validator.

## Problem Statement

The builder should not maintain a separate weaker interpretation of DOT. If it does:

1. the UI can drift from engine semantics
2. linting becomes inconsistent
3. round-trip editing becomes less trustworthy
4. repair and autofix features become harder to implement safely

## Work Items

1. Replace the ad-hoc JS DOT parser path with server-backed parse and normalize endpoints.
2. Return the canonical graph model from Elixir for builder rendering.
3. Show validator diagnostics inline in the builder.
4. Add autofix suggestions for common graph issues.
5. Add canonical DOT formatting and stable serialization.
6. Add graph templates and graph transforms as composable authoring actions.

## Deliverables

1. Canonical parse/normalize API
2. Builder lint panel
3. Stable DOT formatting
4. Autofix actions
5. Trustworthy round-trip editing

## Success Criteria

This workstream is done when:

1. the builder no longer depends on a separate homegrown DOT interpretation for correctness
2. diagnostics shown in the UI match the engine and API behavior
3. graph serialization is stable and canonical
4. round-trip authoring is reliable enough to support advanced repair and refactoring tools
