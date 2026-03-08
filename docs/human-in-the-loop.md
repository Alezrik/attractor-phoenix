# Human-in-the-Loop

`wait.human` is the AttractorEx mechanism for pausing pipeline execution until a person, service, or test adapter provides an answer.

## Core Modules

- `AttractorEx.Handlers.WaitForHuman`
- `AttractorEx.HumanGate`
- `AttractorEx.Interviewer`
- `AttractorEx.Interviewers.Payload`
- `AttractorEx.Interviewers.*`

## Flow

When the engine reaches a `wait.human` node:

1. Outgoing edges are converted into normalized choices.
2. The runtime looks for an answer in context first.
3. If no answer is present, an interviewer adapter is invoked.
4. The answer is normalized into a single or multi-select payload.
5. The handler returns an `AttractorEx.Outcome` with suggested next targets.

## Supported Interviewers

The library ships with several adapters:

- `AutoApprove` for deterministic test or local automation flows.
- `Console` for terminal-driven interaction.
- `Callback` for embedding custom functions.
- `Queue` for list- or `Agent`-backed scripted answers.
- `Recording` for wrapping another interviewer while capturing events.
- `Server` for HTTP-backed pending-question workflows.

## Question Model

`AttractorEx.Interviewers.Payload` normalizes questions and answers into a shared contract with fields like:

- `type`
- `options`
- `default`
- `multiple`
- `required`
- `metadata.input_mode`

That shared shape is what allows the HTTP server, console adapter, tests, and custom callbacks to behave consistently.

## Routing Semantics

`wait.human` supports:

- direct choice keys
- labels
- node IDs
- structured answer payloads
- defaults on blank answers or timeouts
- multi-select answers
- skip and timeout signaling

If a response cannot be matched, the handler falls back to the first outgoing choice, which keeps the pipeline executable even under ambiguous input.
