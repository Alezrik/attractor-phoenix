defmodule AttractorPhoenixWeb.BenchmarkLiveTest do
  use AttractorPhoenixWeb.ConnCase

  import Phoenix.LiveViewTest

  test "renders the benchmark mission page with scorecard, references, and roadmap", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/benchmark")

    assert html =~ "Product strategy console"
    assert has_element?(view, "#benchmark-page")
    assert has_element?(view, "#benchmark-score-panel")
    assert has_element?(view, "#benchmark-blocked-criteria")
    assert has_element?(view, "#benchmark-route-links")
    assert has_element?(view, "#benchmark-proof-packet")
    assert has_element?(view, "#reference-set")
    assert has_element?(view, "#benchmark-dimensions")
    assert has_element?(view, "#required-evidence")
    assert has_element?(view, "#anti-claim-rules")
    assert has_element?(view, "#premium-features")
    assert has_element?(view, "#leadership-criteria-summary")
    assert has_element?(view, "#leadership-criteria")
    assert has_element?(view, "#suggested-execution-order")
    assert has_element?(view, "#immediate-next-steps")
    assert has_element?(view, "#premium-risks")
    assert has_element?(view, "#anti-goals")
    assert has_element?(view, "#strategic-priorities")
    assert has_element?(view, "#review-cadence")
    assert has_element?(view, "#conformance-scoreboard")
    assert has_element?(view, "#conformance-suites")
    assert has_element?(view, "#conformance-gap-ledger")
    assert has_element?(view, "#conformance-commands")
    assert html =~ "samueljklee-attractor"
    assert html =~ "TheFellow-fkyeah"
    assert html =~ "weighted composite score out of 5.0"
    assert html =~ "4.2"
    assert html =~ "See score, blockers, and execution routes"
    assert html =~ "Conformance scoreboard"
    assert html =~ "Benchmark proof boundary"
    assert html =~ "partially supported by"

    assert html =~
             "AttractorPhoenix.Benchmark.summary() and AttractorPhoenix.Conformance.summary()"

    assert html =~
             "raise blocked leadership criteria with executable proof before broadening benchmark claims"

    assert html =~ "CONF-STATE-001"
    assert html =~ "mix test test/attractor_ex/conformance"
    assert html =~ "Durable runtime and replayable state"
    assert html =~ "Runtime state is still in-memory in the HTTP manager."
    assert html =~ "Breakpoints and pause-on-stage debugging"
    assert html =~ "Step-through execution mode"

    assert html =~
             "The main dashboard and run views are subscription-driven, not primarily poll-driven."

    assert html =~ "Persistent run store"

    assert html =~
             "Turning the project into a generic workflow product unrelated to Attractor semantics"

    assert html =~ "not claimable yet"
  end

  test "benchmark route is linked from the top navigation", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/benchmark")

    assert html =~ ~s(href="/benchmark")
    assert html =~ "Benchmark"
  end
end
