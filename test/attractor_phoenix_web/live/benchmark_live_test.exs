defmodule AttractorPhoenixWeb.BenchmarkLiveTest do
  use AttractorPhoenixWeb.ConnCase

  import Phoenix.LiveViewTest

  test "renders the benchmark mission page with scorecard, references, and roadmap", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/benchmark")

    assert html =~ "Mission and competitive benchmark"
    assert has_element?(view, "#benchmark-page")
    assert has_element?(view, "#benchmark-score-panel")
    assert has_element?(view, "#reference-set")
    assert has_element?(view, "#benchmark-dimensions")
    assert has_element?(view, "#required-evidence")
    assert has_element?(view, "#anti-claim-rules")
    assert has_element?(view, "#strategic-priorities")
    assert has_element?(view, "#review-cadence")
    assert html =~ "samueljklee-attractor"
    assert html =~ "TheFellow-fkyeah"
    assert html =~ "weighted composite score out of 5.0"
    assert html =~ "4.2"
    assert html =~ "Durable runtime and replayable state"
    assert html =~ "Runtime state is still in-memory in the HTTP manager."
    assert html =~ "not claimable yet"
  end

  test "benchmark route is linked from the top navigation", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/benchmark")

    assert html =~ ~s(href="/benchmark")
    assert html =~ "Benchmark"
  end
end
