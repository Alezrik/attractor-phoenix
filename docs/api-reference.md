# attractor_phoenix v0.1.0 - API Reference

## Modules

- [AttractorPhoenix](AttractorPhoenix.md): AttractorPhoenix keeps the contexts that define your domain
and business logic.
- [AttractorPhoenix.Mailer](AttractorPhoenix.Mailer.md)
- [AttractorPhoenix.PipelineLibrary](AttractorPhoenix.PipelineLibrary.md): File-backed storage for reusable builder pipelines.
- [AttractorPhoenixWeb](AttractorPhoenixWeb.md): The entrypoint for defining your web interface, such
as controllers, components, channels, and so on.
- [AttractorPhoenixWeb.AttractorChannel](AttractorPhoenixWeb.AttractorChannel.md): Phoenix Channel that streams `AttractorEx` pipeline snapshots and live updates.

- [AttractorPhoenixWeb.CoreComponents](AttractorPhoenixWeb.CoreComponents.md): Provides core UI components.
- [AttractorPhoenixWeb.DashboardLive](AttractorPhoenixWeb.DashboardLive.md)
- [AttractorPhoenixWeb.Endpoint](AttractorPhoenixWeb.Endpoint.md)
- [AttractorPhoenixWeb.ErrorHTML](AttractorPhoenixWeb.ErrorHTML.md): This module is invoked by your endpoint in case of errors on HTML requests.
- [AttractorPhoenixWeb.ErrorJSON](AttractorPhoenixWeb.ErrorJSON.md): This module is invoked by your endpoint in case of errors on JSON requests.
- [AttractorPhoenixWeb.Gettext](AttractorPhoenixWeb.Gettext.md): A module providing Internationalization with a gettext-based API.
- [AttractorPhoenixWeb.Layouts](AttractorPhoenixWeb.Layouts.md): This module holds layouts and related functionality
used by your application.

- [AttractorPhoenixWeb.PageController](AttractorPhoenixWeb.PageController.md)
- [AttractorPhoenixWeb.PageHTML](AttractorPhoenixWeb.PageHTML.md): This module contains pages rendered by PageController.
- [AttractorPhoenixWeb.PipelineBuilderLive](AttractorPhoenixWeb.PipelineBuilderLive.md)
- [AttractorPhoenixWeb.PipelineLibraryLive](AttractorPhoenixWeb.PipelineLibraryLive.md)
- [AttractorPhoenixWeb.Router](AttractorPhoenixWeb.Router.md)
- [AttractorPhoenixWeb.Telemetry](AttractorPhoenixWeb.Telemetry.md)
- [AttractorPhoenixWeb.UserSocket](AttractorPhoenixWeb.UserSocket.md)
- [AttractorEx.SimulationBackend](AttractorEx.SimulationBackend.md): Minimal fallback backend used by `AttractorEx.Handlers.Codergen` in tests and demos.

- EntryPoints
  - [AttractorEx](AttractorEx.md): Public entry point for the AttractorEx pipeline engine.
  - [AttractorEx.Condition](AttractorEx.Condition.md): Evaluates the compact condition-expression language used on pipeline edges.
  - [AttractorEx.Engine](AttractorEx.Engine.md): Core execution engine for AttractorEx pipelines.
  - [AttractorEx.Parser](AttractorEx.Parser.md): Parses the supported Attractor DOT subset into `AttractorEx.Graph`.
  - [AttractorEx.StatusContract](AttractorEx.StatusContract.md): Serializes handler outcomes into the `status.json` artifact contract.
  - [AttractorEx.Validator](AttractorEx.Validator.md): Validates parsed graphs against the supported Attractor runtime contract.

- GraphModel
  - [AttractorEx.Checkpoint](AttractorEx.Checkpoint.md): Serializable checkpoint snapshot for resumable pipeline execution.
  - [AttractorEx.Edge](AttractorEx.Edge.md): Runtime representation of a directed edge between two nodes.
  - [AttractorEx.Graph](AttractorEx.Graph.md): Normalized in-memory representation of a parsed pipeline graph.
  - [AttractorEx.ModelStylesheet](AttractorEx.ModelStylesheet.md): Parses and applies the `model_stylesheet` graph attribute.
  - [AttractorEx.Node](AttractorEx.Node.md): Runtime representation of a pipeline node.
  - [AttractorEx.Outcome](AttractorEx.Outcome.md): Standard result value returned by node handlers.

- Handlers
  - [AttractorEx.Handler](AttractorEx.Handler.md): Behaviour implemented by all executable node handlers.
  - [AttractorEx.HandlerRegistry](AttractorEx.HandlerRegistry.md): Resolves node types to executable handler modules.
  - [AttractorEx.Handlers.Codergen](AttractorEx.Handlers.Codergen.md): Handler for LLM-driven `codergen` stages.
  - [AttractorEx.Handlers.Conditional](AttractorEx.Handlers.Conditional.md): Handler for explicit conditional nodes.
  - [AttractorEx.Handlers.Default](AttractorEx.Handlers.Default.md): Fallback handler used when a node type does not need special runtime behavior.

  - [AttractorEx.Handlers.Exit](AttractorEx.Handlers.Exit.md): Handler for terminal `exit` nodes.

  - [AttractorEx.Handlers.Parallel](AttractorEx.Handlers.Parallel.md): Handler for parallel branch fan-out nodes.
  - [AttractorEx.Handlers.ParallelFanIn](AttractorEx.Handlers.ParallelFanIn.md): Handler for `parallel.fan_in` nodes that select a best branch result.

  - [AttractorEx.Handlers.StackManagerLoop](AttractorEx.Handlers.StackManagerLoop.md): Handler for manager-loop nodes that observe and steer a child workflow.
  - [AttractorEx.Handlers.Start](AttractorEx.Handlers.Start.md): Handler for the synthetic `start` node.

  - [AttractorEx.Handlers.Tool](AttractorEx.Handlers.Tool.md): Handler for shell-command tool nodes.
  - [AttractorEx.Handlers.WaitForHuman](AttractorEx.Handlers.WaitForHuman.md): Handler for `wait.human` nodes.

- HumanInTheLoop
  - [AttractorEx.HumanGate](AttractorEx.HumanGate.md): Helper functions for building and matching `wait.human` choices.
  - [AttractorEx.Interviewer](AttractorEx.Interviewer.md): Behaviour for human-in-the-loop adapters used by `wait.human`.
  - [AttractorEx.Interviewers.AutoApprove](AttractorEx.Interviewers.AutoApprove.md): Deterministic interviewer that auto-selects a configured answer or the first choice.
  - [AttractorEx.Interviewers.Callback](AttractorEx.Interviewers.Callback.md): Interviewer that delegates question handling to caller-provided functions.

  - [AttractorEx.Interviewers.Console](AttractorEx.Interviewers.Console.md): Terminal-backed interviewer for local manual runs.
  - [AttractorEx.Interviewers.Payload](AttractorEx.Interviewers.Payload.md): Shared question and answer normalization for interviewer adapters.
  - [AttractorEx.Interviewers.Queue](AttractorEx.Interviewers.Queue.md): Interviewer backed by a list or `Agent` queue of pre-seeded answers.

  - [AttractorEx.Interviewers.Recording](AttractorEx.Interviewers.Recording.md): Decorator interviewer that records questions, answers, and info payloads.
  - [AttractorEx.Interviewers.Server](AttractorEx.Interviewers.Server.md): HTTP-oriented interviewer used by `AttractorEx.HTTP`.

- HTTPService
  - [AttractorEx.HTTP](AttractorEx.HTTP.md): Convenience entry point for starting and stopping the AttractorEx HTTP service.
  - [AttractorEx.HTTP.GraphRenderer](AttractorEx.HTTP.GraphRenderer.md): Renders parsed graphs into presentation-friendly HTTP formats.
  - [AttractorEx.HTTP.Manager](AttractorEx.HTTP.Manager.md): GenServer that owns the in-memory state for HTTP-managed pipeline runs.
  - [AttractorEx.HTTP.Router](AttractorEx.HTTP.Router.md): Plug router exposing the AttractorEx HTTP API.

- PhoenixAdapter
  - [AttractorExPhx](AttractorExPhx.md): Phoenix-facing adapter layer for `AttractorEx`.
  - [AttractorExPhx.Client](AttractorExPhx.Client.md): Req-based client for the `AttractorEx` HTTP control plane.
  - [AttractorExPhx.HTTPServer](AttractorExPhx.HTTPServer.md): Supervision-friendly HTTP server wrapper for `AttractorEx`.
  - [AttractorExPhx.PubSub](AttractorExPhx.PubSub.md): Phoenix PubSub bridge for `AttractorEx` pipeline updates.

- UnifiedLLM
  - [AttractorEx.LLM.Client](AttractorEx.LLM.Client.md): Provider-agnostic LLM client used by codergen nodes and agent sessions.
  - [AttractorEx.LLM.Message](AttractorEx.LLM.Message.md): Unified chat message struct used in LLM requests.
  - [AttractorEx.LLM.MessagePart](AttractorEx.LLM.MessagePart.md): Tagged content part used by `AttractorEx.LLM.Message`.
  - [AttractorEx.LLM.ProviderAdapter](AttractorEx.LLM.ProviderAdapter.md): Behaviour implemented by unified LLM provider adapters.
  - [AttractorEx.LLM.Request](AttractorEx.LLM.Request.md): Unified request struct for provider-agnostic LLM completions.
  - [AttractorEx.LLM.Response](AttractorEx.LLM.Response.md): Unified response struct returned by provider adapters.

  - [AttractorEx.LLM.StreamEvent](AttractorEx.LLM.StreamEvent.md): Event struct used by streaming LLM adapters.
  - [AttractorEx.LLM.Usage](AttractorEx.LLM.Usage.md): Normalized token-usage counters returned by LLM responses and streams.

- AgentLoop
  - [AttractorEx.Agent.ApplyPatch](AttractorEx.Agent.ApplyPatch.md): Applies `apply_patch` v4a-style filesystem updates against a local execution environment.
  - [AttractorEx.Agent.BuiltinTools](AttractorEx.Agent.BuiltinTools.md): Built-in coding-agent tools backed by an `ExecutionEnvironment`.
  - [AttractorEx.Agent.Event](AttractorEx.Agent.Event.md): Typed session event emitted by `AttractorEx.Agent.Session`.
  - [AttractorEx.Agent.ExecutionEnvironment](AttractorEx.Agent.ExecutionEnvironment.md): Execution-environment behaviour for coding-agent sessions.
  - [AttractorEx.Agent.LocalExecutionEnvironment](AttractorEx.Agent.LocalExecutionEnvironment.md): Local filesystem-backed execution environment for agent sessions.
  - [AttractorEx.Agent.ProviderProfile](AttractorEx.Agent.ProviderProfile.md): Provider-aligned configuration for the coding-agent loop.
  - [AttractorEx.Agent.Session](AttractorEx.Agent.Session.md): Stateful coding-agent loop built on top of `AttractorEx.LLM.Client`.
  - [AttractorEx.Agent.SessionConfig](AttractorEx.Agent.SessionConfig.md): Runtime configuration for coding-agent sessions.
  - [AttractorEx.Agent.Tool](AttractorEx.Agent.Tool.md): Definition of a callable tool exposed to an agent session.
  - [AttractorEx.Agent.ToolCall](AttractorEx.Agent.ToolCall.md): Normalized representation of a tool call requested by the model.

  - [AttractorEx.Agent.ToolRegistry](AttractorEx.Agent.ToolRegistry.md): Lightweight registry of agent tools keyed by name.

  - [AttractorEx.Agent.ToolResult](AttractorEx.Agent.ToolResult.md): Normalized representation of a tool execution result fed back to the model.

- Transforms
  - [AttractorEx.Transforms.VariableExpansion](AttractorEx.Transforms.VariableExpansion.md): Built-in graph transform that expands simple runtime variables such as `$goal`.

## Mix Tasks

- [mix coverage.gate](Mix.Tasks.Coverage.Gate.md): Enforces the minimum coverage threshold configured in `coveralls.json`.

