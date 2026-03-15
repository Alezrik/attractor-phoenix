# 02. Runtime Foundation

This workstream exists to make `attractor-phoenix` operationally deeper than the current reference set.

Primary inspiration:

1. `kilroy` for durable run state, snapshots, checkpointing, and resume depth
2. `samueljklee-attractor` for treating events, checkpointing, SSE, and cancellation as core runtime behavior

## Goal

Replace ephemeral execution tracking with durable, typed, replayable runtime state.

## Why This Matters

Without durable runtime state, the project cannot credibly outrank the strongest server- and runtime-oriented references.

This workstream is the foundation for:

1. reliable replay
2. restart-safe resume
3. a real debugger
4. large run histories
5. serious operator workflows

## Planned Capabilities

1. Persistent run records
2. Persistent event history
3. Persistent checkpoint snapshots
4. Artifact indexing
5. Replay and resume from persisted run state
6. Restart-safe recovery behavior

## Work Items

1. Introduce a persistent run-state layer behind the HTTP manager.
2. Define typed records for run metadata, events, questions, checkpoints, and artifacts.
3. Store event history incrementally rather than only in process memory.
4. Add restart-safe run loading on boot.
5. Add event replay support for SSE and Phoenix subscriptions.
6. Strengthen resume invariants and tests around persisted checkpoints.

## Deliverables

1. Durable run store abstraction
2. Migration path from in-memory manager state
3. Restart-safe run loading
4. Replayable events API
5. Strong resume regression tests

## Success Criteria

This workstream is done when:

1. runs, events, and questions survive process restarts
2. checkpoints are durable and resumable without relying on transient process state
3. event replay works for SSE and Phoenix consumers
4. regression tests prove replay and resume invariants
