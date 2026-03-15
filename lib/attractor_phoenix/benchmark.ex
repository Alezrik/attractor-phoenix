defmodule AttractorPhoenix.Benchmark do
  @moduledoc """
  Canonical benchmark contract and current leadership posture for the product surface.
  """

  alias AttractorPhoenix.Conformance

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

  def summary do
    composite = composite_score(@dimensions)

    %{
      title: "Mission And Competitive Benchmark",
      mission_dimensions: @mission_dimensions,
      target_capabilities: @target_capabilities,
      competitive_claim_rules: @competitive_claim_rules,
      reference_set: @reference_set,
      benchmark_standard: @benchmark_standard,
      dimensions: @dimensions,
      conformance: @conformance,
      composite_score: composite,
      leadership_ready?: leadership_ready?(@dimensions),
      current_position: @current_position,
      required_evidence: @required_evidence,
      scoring_rubric: @scoring_rubric,
      leadership_gate: @leadership_gate,
      strategic_priorities: @strategic_priorities,
      review_cadence: @review_cadence,
      anti_claim_rules: @anti_claim_rules
    }
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
