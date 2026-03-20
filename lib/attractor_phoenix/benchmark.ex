defmodule AttractorPhoenix.Benchmark do
  @moduledoc """
  Canonical benchmark contract and current leadership posture for the product surface.
  """

  alias AttractorPhoenix.Conformance
  alias AttractorPhoenix.TrustProof

  @conformance Conformance.summary()

  @mission_dimensions [
    "Runtime capability",
    "Conformance and implementation rigor",
    "Operator experience and premium product features"
  ]

  @target_capabilities [
    "Durable execution and resume semantics",
    "Stronger black-box proof of behavior",
    "A first-class debugger and operator control plane",
    "A cohesive Attractor + coding-agent + unified-LLM story"
  ]

  @competitive_claim_rules [
    "Runtime depth is stronger than the best runtime-focused reference.",
    "Conformance evidence quality is stronger than the best conformance-focused reference.",
    "Operator experience is stronger than the best dashboard-focused reference.",
    "Public documentation accurately states both strengths and known gaps."
  ]

  @reference_set [
    "samueljklee-attractor",
    "TheFellow-fkyeah",
    "kilroy",
    "brynary-attractor",
    "smartcomputer-ai-forge",
    "attractor",
    "aliciapaz-attractor-rb"
  ]

  @benchmark_standard [
    "Match or exceed samueljklee-attractor on execution and server surface.",
    "Match or exceed TheFellow-fkyeah on conformance evidence quality.",
    "Match or exceed kilroy on durable run state and resume fidelity.",
    "Match or exceed brynary-attractor on integration coherence across runtime, agent loop, and unified-LLM abstractions.",
    "Match or exceed attractor on dashboard and operator usability.",
    "Keep explicit honesty like aliciapaz-attractor-rb and smartcomputer-ai-forge around what remains incomplete."
  ]

  @dimensions [
    %{
      id: :runtime,
      label: "Runtime capability and durability",
      short_label: "Runtime",
      weight: 0.40,
      score: 2.0,
      status: "Below leadership bar",
      strengths: [
        "Broad parser, validator, engine, handlers, HTTP service, SSE, and resume support.",
        "Phoenix dashboard already inspects live pipelines through the runtime HTTP surface."
      ],
      gaps: [
        "Runtime state is still in-memory in the HTTP manager.",
        "Restart-safe persistence and replay evidence are not in place yet."
      ],
      evidence: [
        "Live dashboard over the HTTP runtime contract",
        "Focused engine, HTTP, and handler tests"
      ]
    },
    %{
      id: :conformance,
      label: "Conformance and proof quality",
      short_label: "Conformance",
      weight: 0.30,
      score: @conformance.score,
      status: "Strong implementation with documented evidence",
      strengths: [
        "Published benchmark suites now cover parsing, runtime, state, transport, agent loop, and unified LLM behavior.",
        "#{@conformance.implemented_scenarios}/#{@conformance.total_scenarios} published conformance scenarios are implemented in a dedicated black-box harness."
      ],
      gaps: Enum.map(@conformance.gap_ledger, & &1.summary),
      evidence: [
        "Black-box conformance suites under test/attractor_ex/conformance",
        "Published scoreboard and gap ledger on the benchmark page and docs"
      ]
    },
    %{
      id: :operator,
      label: "Operator experience and product surface",
      short_label: "Operator",
      weight: 0.20,
      score: 2.5,
      status: "Functional but materially incomplete",
      strengths: [
        "Dashboard, builder, setup, and pipeline library are already productized LiveView surfaces.",
        "Operators can inspect runs, answer questions, cancel runs, and inspect graph formats from the browser."
      ],
      gaps: [
        "The main UI is still more inspector than debugger-grade operator console.",
        "Debugger workflows, replay controls, and richer run ergonomics are still missing."
      ],
      evidence: [
        "LiveView dashboard, builder, setup, and library routes",
        "Question-answering and cancellation flows covered by LiveView tests"
      ]
    },
    %{
      id: :integration,
      label: "Integration coherence across Attractor + coding-agent + unified LLM",
      short_label: "Integration",
      weight: 0.10,
      score: 3.0,
      status: "Production-credible baseline",
      strengths: [
        "Human-in-the-loop support, coding-agent loop primitives, and unified LLM foundations already exist in the same repository.",
        "The builder and setup flows already connect the Phoenix product surface to unified LLM-backed graph authoring."
      ],
      gaps: [
        "Several unified-LLM and appendix-level spec areas remain partial or not implemented.",
        "A single benchmark scenario proving runtime + human gate + agent loop + unified LLM behavior is not yet published."
      ],
      evidence: [
        "Agent-loop and unified-LLM modules in AttractorEx",
        "Builder creation flow using the configured provider stack"
      ]
    }
  ]

  @current_position %{
    strengths: [
      "Broad AttractorEx parser, validator, engine, handlers, HTTP service, SSE, and resume support.",
      "Human-in-the-loop support, coding-agent loop primitives, and unified LLM foundations.",
      "Published documentation and maintained compliance matrices.",
      "Phoenix LiveView surfaces for dashboard, builder, setup, and pipeline library."
    ],
    gaps: [
      "Runtime state is still in-memory in the HTTP manager.",
      "The main UI is more inspector than operator console.",
      "The builder has its own JavaScript DOT interpretation path.",
      "Several unified-LLM and appendix-level spec areas remain partial or not implemented.",
      "Conformance evidence is strong, but not yet packaged as a visible black-box benchmark suite against competing implementations."
    ]
  }

  @required_evidence [
    "Runtime: restart-safe persistence and replay tests that pass from a clean boot.",
    "Conformance: black-box fixtures and runners with published pass/fail output.",
    "Operator surface: live run inspection and debugger workflows demonstrable without internal-only tooling.",
    "Integration: end-to-end scenario proving runtime + human gate + agent loop + unified LLM behavior in one reproducible path."
  ]

  @scoring_rubric [
    "`0`: not implemented",
    "`1`: partial prototype, not dependable",
    "`2`: functional but materially incomplete",
    "`3`: production-credible baseline",
    "`4`: strong implementation with documented evidence",
    "`5`: best-in-set quality with benchmark-grade proof"
  ]

  @leadership_gate [
    "Composite score >= 4.2",
    "No dimension below 4.0",
    "No hidden known gaps in public docs"
  ]

  @strategic_priorities [
    "Durable runtime and replayable state",
    "First-class debugger",
    "Canonical builder fidelity",
    "Black-box conformance leadership",
    "Completion of the LLM and agent-platform story",
    "A cohesive operator-grade Phoenix product"
  ]

  @review_cadence [
    "Weekly internal score review against the rubric.",
    "Milestone-based public docs refresh when a dimension score changes.",
    "Pre-release leadership check requiring evidence links for all >= 4.0 claims."
  ]

  @anti_claim_rules [
    "Durability or replay depends on in-memory-only state.",
    "Conformance status is not backed by executable fixtures.",
    "Debugger capabilities exist only as internal diagnostics.",
    "Unified LLM or agent-loop claims are broader than current implemented behavior."
  ]

  @premium_features [
    %{
      id: :breakpoints,
      label: "Breakpoints and pause-on-stage debugging",
      status: "Blocked on debugger MVP",
      summary:
        "Needs a dedicated debugger timeline and replay-aware operator controls before pause semantics are trustworthy.",
      dependency: "Debugger MVP and replay-aware transport"
    },
    %{
      id: :step_through,
      label: "Step-through execution mode",
      status: "Blocked on debugger MVP",
      summary:
        "Depends on durable run state plus stage-level replay so stepping is deterministic instead of inspect-only.",
      dependency: "Typed run state and replay controls"
    },
    %{
      id: :heatmaps,
      label: "Stage heatmaps and graph overlays",
      status: "Design-ready",
      summary:
        "The graph and event surfaces exist, but the operator UI still needs debugger-grade event aggregation and visual overlays.",
      dependency: "Debugger timeline and richer event aggregation"
    },
    %{
      id: :search,
      label: "Artifact and run search",
      status: "Foundation exists",
      summary:
        "Persisted run artifacts are indexed by the run store, but there is no operator-grade search surface yet.",
      dependency: "Persistent run metadata and operator search UI"
    },
    %{
      id: :saved_views,
      label: "Saved debugger views",
      status: "Not started",
      summary:
        "Requires a debugger surface worth saving plus stable filter/view state to persist.",
      dependency: "Debugger MVP and user-facing filter state"
    },
    %{
      id: :share_links,
      label: "Shareable run links",
      status: "Partially enabled",
      summary:
        "Routes and run identifiers already exist, but sharable debugger deep links are still missing.",
      dependency: "Dedicated run/debugger routes and view state encoding"
    },
    %{
      id: :annotations,
      label: "Operator annotations on runs and events",
      status: "Not started",
      summary:
        "Needs persistent operator-authored metadata on top of the current runtime event ledger.",
      dependency: "Persistent run store schema for operator notes"
    },
    %{
      id: :quality_scoring,
      label: "Pipeline quality scoring and readiness checks before execution",
      status: "Foundation exists",
      summary:
        "Canonical parser/validator work is in place, but the product still lacks a preflight scorecard in the builder.",
      dependency: "Builder canonicalization and pre-execution checks"
    }
  ]

  @leadership_criteria [
    %{
      id: :restart_survival,
      criterion: "Runs, events, checkpoints, and question state survive process restarts.",
      met?: true,
      evidence:
        "HTTP manager reload and replay tests plus file-backed run store support restart recovery.",
      blocker: nil
    },
    %{
      id: :resume_replay_tests,
      criterion: "Resume and replay behavior are proven by focused regression tests.",
      met?: true,
      evidence:
        "Engine, HTTP manager, transport, and Phoenix PubSub tests exercise checkpoint resume and replay windows.",
      blocker: nil
    },
    %{
      id: :subscription_driven_views,
      criterion:
        "The main dashboard and run views are subscription-driven, not primarily poll-driven.",
      met?: false,
      evidence:
        "Phoenix PubSub replay-filtered subscriptions exist for LiveViews and other OTP consumers.",
      blocker:
        "Dashboard LiveView still reads from the HTTP surface rather than subscribing as the primary transport."
    },
    %{
      id: :canonical_builder,
      criterion: "The builder uses the canonical Elixir parser and validator model.",
      met?: false,
      evidence:
        "Authoring APIs already expose canonical parse, normalize, transform, and validation results from Elixir.",
      blocker:
        "The browser builder still keeps its own DOT interpretation path instead of fully delegating to the canonical model."
    },
    %{
      id: :dedicated_debugger,
      criterion:
        "A dedicated debugger exists with timeline, diffs, artifacts, and replay controls.",
      met?: false,
      evidence:
        "The dashboard can inspect runs, events, checkpoints, questions, and graph variants.",
      blocker:
        "There is no dedicated debugger workflow with timeline navigation, diffs, or replay controls."
    },
    %{
      id: :published_scoreboard,
      criterion:
        "Public docs include a benchmark or conformance scoreboard tied to executable tests.",
      met?: true,
      evidence:
        "The benchmark page and published docs surface the conformance scoreboard, gap ledger, and runnable test commands.",
      blocker: nil
    },
    %{
      id: :llm_agent_completion,
      criterion:
        "The unified LLM and coding-agent surfaces materially reduce current partial and not-implemented areas.",
      met?: false,
      evidence:
        "Unified LLM and coding-agent primitives are implemented with maintained compliance docs and conformance suites.",
      blocker:
        "The compliance docs still publish meaningful partial and not-implemented areas that need to shrink further."
    },
    %{
      id: :operator_ux_lead,
      criterion:
        "The overall UX is clearly more useful for operators than the best dashboard-oriented reference.",
      met?: false,
      evidence: "The product already has dashboard, builder, setup, and benchmark LiveViews.",
      blocker:
        "Operator workflows are still more inspector-oriented than debugger-grade or premium-feature complete."
    }
  ]

  @suggested_execution_order [
    "Runtime persistence and typed run state",
    "Replay-aware transport and live operator views",
    "Debugger MVP",
    "Builder canonicalization",
    "Conformance harness and published scoreboard",
    "Unified LLM and coding-agent completion",
    "Premium features such as breakpoints and step-through debugging"
  ]

  @premium_risks [
    "Adding more UI without fixing the runtime model underneath it",
    "Keeping multiple incompatible graph interpretations between JS and Elixir",
    "Chasing obscure parser parity before operational depth",
    "Over-claiming completeness without benchmark-grade conformance evidence",
    "Adding premium features that are hard to trust because persistence and replay are weak"
  ]

  @anti_goals [
    "Turning the project into a generic workflow product unrelated to Attractor semantics",
    "Prioritizing cosmetic redesign over runtime depth",
    "Hiding partial areas instead of documenting them",
    "Adding speculative AI features before the unified-LLM foundation is stronger"
  ]

  @immediate_next_steps [
    %{
      id: "02A",
      label: "Persistent run store",
      summary:
        "Finish the durable runtime model so premium operator features sit on restart-safe state."
    },
    %{
      id: "03A",
      label: "Debugger MVP timeline",
      summary:
        "Turn the current inspector surface into a dedicated timeline with replay controls and artifact navigation."
    },
    %{
      id: "04A",
      label: "Canonical parser-backed builder API",
      summary:
        "Remove the split between the browser graph model and the canonical Elixir parser/validator path."
    },
    %{
      id: "05A",
      label: "Black-box conformance fixture harness",
      summary:
        "Keep the leadership claim tied to executable evidence instead of static documentation."
    }
  ]

  def summary do
    composite = composite_score(@dimensions)
    leadership_ready = leadership_ready?(@dimensions)

    base_summary = %{
      title: "Mission And Competitive Benchmark",
      mission_dimensions: @mission_dimensions,
      target_capabilities: @target_capabilities,
      competitive_claim_rules: @competitive_claim_rules,
      reference_set: @reference_set,
      benchmark_standard: @benchmark_standard,
      dimensions: @dimensions,
      conformance: @conformance,
      composite_score: composite,
      leadership_ready?: leadership_ready,
      current_position: @current_position,
      required_evidence: @required_evidence,
      scoring_rubric: @scoring_rubric,
      leadership_gate: @leadership_gate,
      premium_features: @premium_features,
      leadership_criteria: @leadership_criteria,
      leadership_criteria_complete: Enum.count(@leadership_criteria, & &1.met?),
      strategic_priorities: @strategic_priorities,
      suggested_execution_order: @suggested_execution_order,
      review_cadence: @review_cadence,
      anti_claim_rules: @anti_claim_rules,
      premium_risks: @premium_risks,
      anti_goals: @anti_goals,
      immediate_next_steps: @immediate_next_steps
    }

    Map.put(base_summary, :proof_packet, TrustProof.benchmark_record(base_summary))
  end

  defp composite_score(dimensions) do
    dimensions
    |> Enum.reduce(0.0, fn dimension, total ->
      total + dimension.score * dimension.weight
    end)
    |> Float.round(2)
  end

  defp leadership_ready?(dimensions) do
    composite_score(dimensions) >= 4.2 and Enum.all?(dimensions, &(&1.score >= 4.0))
  end
end
