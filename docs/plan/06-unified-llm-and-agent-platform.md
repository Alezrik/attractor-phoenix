# 06. Unified LLM And Agent Platform

This workstream closes the remaining gaps in the AI-facing layers so the project can lead across runtime, agent loop, and provider abstraction together.

Primary inspiration:

1. `brynary-attractor` for coherent boundaries across attractor, coding-agent, and unified-LLM surfaces
2. `smartcomputer-ai-forge` for typed contracts and explicit gap management

## Goal

Reduce the major `partial` and `not implemented` areas in the unified-LLM and coding-agent surfaces.

## Planned Capabilities

1. Native provider adapters for OpenAI, Anthropic, and Gemini
2. Streaming parity and consistent stream translation
3. Typed retry and error taxonomy
4. Prompt caching hooks where providers support them
5. Richer multimodal and content-part round-trip fidelity
6. Incremental typed object streaming
7. Stronger provider-compatibility tests for tool behavior

## Work Items

1. Implement native provider adapters at the unified-LLM layer.
2. Add streaming parity and normalized stream translation.
3. Add typed retry and error handling with backoff and retry-after semantics.
4. Add prompt caching support where available.
5. Add stronger multimodal/message-part round-trip handling.
6. Add incremental typed object streaming rather than full accumulation only.
7. Expand provider-compatibility tests for agent-loop tool semantics and host event behavior.

## Deliverables

1. Native adapters and streaming support
2. Retry and error model
3. Typed object streaming
4. Expanded provider conformance coverage
5. Reduced partial and not-implemented status in compliance docs

## Success Criteria

This workstream is done when:

1. the compliance docs materially improve in the unified-LLM and coding-agent areas
2. provider behavior is stronger and more uniform
3. streaming and retry behavior are first-class rather than partial scaffolding
4. the system tells a coherent full-stack story across runtime, agent loop, and provider abstractions
