defmodule AttractorPhoenixWeb.DebuggerLiveTest do
  use AttractorPhoenixWeb.ConnCase

  alias AttractorExPhx.Client, as: AttractorAPI

  import Phoenix.LiveViewTest

  test "debugger shows run-state, checkpoint truth, and human-gate action framing", %{conn: conn} do
    pipeline_id = "debugger_gate_#{System.unique_integer([:positive])}"

    assert {:ok, %{"pipeline_id" => ^pipeline_id}} =
             AttractorAPI.create_pipeline(wait_human_dot(), %{}, pipeline_id: pipeline_id)

    wait_for_questions(pipeline_id)

    {:ok, view, _html} = live(conn, ~p"/runs/#{pipeline_id}/debugger?focus=questions")

    assert has_element?(view, "#run-debugger-page")
    assert has_element?(view, "#debugger-run-state", "Awaiting human action")
    assert has_element?(view, "#debugger-latest-update")
    assert has_element?(view, "#debugger-checkpoint-detail")
    assert has_element?(view, "#debugger-human-gate-owner", "Operator review required")
    assert has_element?(view, "#debugger-recovery-summary")
    assert has_element?(view, "#debugger-recovery-label", "Human gate blocks progress")
    assert has_element?(view, "#debugger-recovery-next-step", "Approve release?")
    assert has_element?(view, "#debugger-recovery-effect", "does not retry, replay, or resume")
    assert has_element?(view, "#debugger-human-gate-summary")
    assert has_element?(view, "#debugger-human-gate-action", "Approve release?")
    assert has_element?(view, "#debugger-human-gate-effect", "does not retry, replay, or resume")
    assert has_element?(view, "#debugger-cancel-effect", "stops active work")
    assert has_element?(view, "a[href='/runs/#{pipeline_id}']", "Return to run detail")
  end

  test "debugger keeps route continuity from run detail for question-focused blocked runs", %{
    conn: conn
  } do
    pipeline_id = "debugger_route_#{System.unique_integer([:positive])}"

    assert {:ok, %{"pipeline_id" => ^pipeline_id}} =
             AttractorAPI.create_pipeline(wait_human_dot(), %{}, pipeline_id: pipeline_id)

    wait_for_questions(pipeline_id)

    {:ok, run_view, _html} = live(conn, ~p"/runs/#{pipeline_id}")

    assert has_element?(
             run_view,
             "a[href='/runs/#{pipeline_id}/debugger?focus=questions']",
             "Open Human-Gate Debugger"
           )

    {:ok, debugger_view, _html} = live(conn, ~p"/runs/#{pipeline_id}/debugger?focus=questions")

    assert has_element?(debugger_view, "#run-debugger-page")
    assert has_element?(debugger_view, "#debugger-human-gate-summary")
    assert has_element?(debugger_view, "#debugger-recovery-summary")
  end

  test "human-gate answer flow leaves explicit post-answer confirmation across debugger and run detail",
       %{conn: conn} do
    pipeline_id = "debugger_resolution_#{System.unique_integer([:positive])}"

    assert {:ok, %{"pipeline_id" => ^pipeline_id}} =
             AttractorAPI.create_pipeline(wait_human_dot(), %{}, pipeline_id: pipeline_id)

    wait_for_questions(pipeline_id)

    {:ok, run_view, _html} = live(conn, ~p"/runs/#{pipeline_id}")

    assert has_element?(
             run_view,
             "a[href='/runs/#{pipeline_id}/debugger?focus=questions']",
             "Open Human-Gate Debugger"
           )

    {:ok, debugger_view, _html} = live(conn, ~p"/runs/#{pipeline_id}/debugger?focus=questions")

    debugger_view
    |> element("#debugger-answer-form-gate")
    |> render_submit(%{"question_id" => "gate", "response" => %{"choice" => "A"}})

    wait_for_pipeline_status(pipeline_id, "success")

    refute has_element?(debugger_view, "#debugger-answer-form-gate")
    assert has_element?(debugger_view, "#debugger-run-state", "Completed")
    assert has_element?(debugger_view, "#debugger-human-gate-resolution")

    assert has_element?(
             debugger_view,
             "#debugger-human-gate-resolution-label",
             "Question answered"
           )

    assert has_element?(
             debugger_view,
             "#debugger-human-gate-resolution-question",
             "Approve release?"
           )

    assert has_element?(
             debugger_view,
             "#debugger-human-gate-resolution-detail",
             "No pending human-gate questions remain on this route."
           )

    assert has_element?(
             debugger_view,
             "#debugger-human-gate-resolution-known-limit",
             "does not prove retry, replay, resume, or any broader recovery semantics"
           )

    {:ok, resolved_run_view, _html} = live(conn, ~p"/runs/#{pipeline_id}")

    refute has_element?(resolved_run_view, "#answer-form-gate")
    assert has_element?(resolved_run_view, "#run-current-state", "Completed")

    assert has_element?(
             resolved_run_view,
             "#run-questions-empty",
             "No open human-in-the-loop questions."
           )
  end

  defp wait_human_dot do
    """
    digraph attractor {
      start [shape=Mdiamond]
      gate [shape=hexagon, prompt="Approve release?", human.timeout="5s"]
      done [shape=Msquare]
      retry [shape=box, prompt="Retry release"]
      start -> gate
      gate -> done [label="[A] Approve"]
      gate -> retry [label="[R] Retry"]
      retry -> done
    }
    """
  end

  defp wait_for_questions(pipeline_id, attempts \\ 100)

  defp wait_for_questions(_pipeline_id, 0), do: flunk("expected pending questions")

  defp wait_for_questions(pipeline_id, attempts) do
    case AttractorAPI.get_pipeline_questions(pipeline_id) do
      {:ok, %{"questions" => [_ | _]}} ->
        :ok

      _ ->
        receive do
        after
          20 -> wait_for_questions(pipeline_id, attempts - 1)
        end
    end
  end

  defp wait_for_pipeline_status(pipeline_id, status, attempts \\ 100)

  defp wait_for_pipeline_status(_pipeline_id, _status, 0), do: flunk("expected pipeline status")

  defp wait_for_pipeline_status(pipeline_id, status, attempts) do
    case AttractorAPI.get_pipeline(pipeline_id) do
      {:ok, %{"status" => ^status}} ->
        :ok

      _ ->
        receive do
        after
          20 -> wait_for_pipeline_status(pipeline_id, status, attempts - 1)
        end
    end
  end
end
