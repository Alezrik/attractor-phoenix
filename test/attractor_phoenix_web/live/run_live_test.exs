defmodule AttractorPhoenixWeb.RunLiveTest do
  use AttractorPhoenixWeb.ConnCase

  alias AttractorExPhx.Client, as: AttractorAPI

  import Phoenix.LiveViewTest

  test "run detail shows recovery truth for failed runs with checkpoint context", %{conn: conn} do
    pipeline_id = "run_detail_failed_#{System.unique_integer([:positive])}"

    assert {:ok, %{"pipeline_id" => ^pipeline_id}} =
             AttractorAPI.create_pipeline(fail_dot(), %{}, pipeline_id: pipeline_id)

    wait_for_pipeline_status(pipeline_id, "fail")

    {:ok, view, _html} = live(conn, ~p"/runs/#{pipeline_id}")

    assert has_element?(view, "#run-state-summary")
    assert has_element?(view, "#run-current-state", "Failed")
    assert has_element?(view, "#run-latest-update")
    assert has_element?(view, "#run-checkpoint-summary")
    assert has_element?(view, "#run-checkpoint-detail")
    assert has_element?(view, "#run-recovery-summary")
    assert has_element?(view, "#run-recovery-label", "Failure with checkpoint context")

    assert has_element?(
             view,
             "#run-recovery-next-step",
             "Compare checkpoint and failure timeline"
           )

    assert has_element?(view, "#run-recovery-effect", "does not resume the run")
    assert has_element?(view, "#run-cancel-effect", "already terminal")
  end

  test "run detail makes human-gate ownership and next action explicit", %{conn: conn} do
    pipeline_id = "run_detail_gate_#{System.unique_integer([:positive])}"

    assert {:ok, %{"pipeline_id" => ^pipeline_id}} =
             AttractorAPI.create_pipeline(wait_human_dot(), %{}, pipeline_id: pipeline_id)

    wait_for_questions(pipeline_id)

    {:ok, view, _html} = live(conn, ~p"/runs/#{pipeline_id}")

    assert has_element?(view, "#run-human-gate-summary")
    assert has_element?(view, "#run-current-state", "Awaiting human action")
    assert has_element?(view, "#run-human-gate-owner", "Operator review required")
    assert has_element?(view, "#run-human-gate-action", "Approve release?")
    assert has_element?(view, "#run-human-gate-effect", "does not retry, replay, or resume")
    assert has_element?(view, "#run-recovery-summary")
    assert has_element?(view, "#run-recovery-label", "Human gate blocks progress")
    assert has_element?(view, "#run-recovery-next-step", "Approve release?")
    assert has_element?(view, "#run-recovery-detail", "selected cancelled packet")

    assert has_element?(
             view,
             "#run-recovery-unavailable",
             "does not generalize retry, replay, restart"
           )

    assert has_element?(
             view,
             "a[href='/runs/#{pipeline_id}/debugger?focus=questions']",
             "Open Human-Gate Debugger"
           )
  end

  test "run detail keeps the selected cancelled packet scoped to failure review", %{conn: conn} do
    pipeline_id = "run_detail_failure_route_#{System.unique_integer([:positive])}"

    assert {:ok, %{"pipeline_id" => ^pipeline_id}} =
             AttractorAPI.create_pipeline(wait_human_dot(), %{}, pipeline_id: pipeline_id)

    wait_for_questions(pipeline_id)
    assert {:ok, %{"status" => "cancelled"}} = AttractorAPI.cancel_pipeline(pipeline_id)
    wait_for_pipeline_status(pipeline_id, "cancelled")

    {:ok, view, _html} = live(conn, ~p"/runs/#{pipeline_id}")

    html = render(view)

    assert has_element?(view, "#run-scoped-failure-review", "Continue in Failure Review")
    assert has_element?(view, "#run-recovery-detail", "checkpoint resume stays blocked")
    assert has_element?(view, "#run-recovery-detail", "human gate is fully cleared")

    assert has_element?(
             view,
             "#run-recovery-unavailable",
             "one explicit checkpoint-backed recovery slice only"
           )

    assert html =~ "/failures?"
    assert html =~ "status=cancelled"
    assert html =~ "questions=open"
    assert html =~ "search=#{pipeline_id}"

    assert has_element?(view, "#run-route-handoff-mode", "Inspection -> failure review -> action")

    assert has_element?(
             view,
             "#run-route-handoff-next-step",
             "Inspect this run first, then continue into the run-scoped failure review before opening the human-gate debugger."
           )

    assert has_element?(
             view,
             "#run-route-handoff-detail",
             "Failure review stays filtered to this run and its current question state"
           )

    assert has_element?(
             view,
             "#run-route-handoff-known-limit",
             "does not imply retry, replay, resume, or broader operator continuity"
           )
  end

  test "run detail exposes and executes the explicit checkpoint resume action", %{conn: conn} do
    pipeline_id = "run_detail_resume_#{System.unique_integer([:positive])}"

    assert {:ok, %{"pipeline_id" => ^pipeline_id}} =
             AttractorAPI.create_pipeline(wait_human_dot(), %{}, pipeline_id: pipeline_id)

    wait_for_questions(pipeline_id)
    assert {:ok, %{"status" => "cancelled"}} = AttractorAPI.cancel_pipeline(pipeline_id)
    wait_for_pipeline_status(pipeline_id, "cancelled")
    assert {:ok, _payload} = AttractorAPI.answer_question(pipeline_id, "gate", "A")
    wait_for_questions_to_clear(pipeline_id)
    wait_for_resume_ready(pipeline_id)

    {:ok, view, _html} = live(conn, ~p"/runs/#{pipeline_id}")

    assert has_element?(view, "#run-recovery-label", "Checkpoint-backed resume available")
    assert has_element?(view, "#run-recovery-detail", "recorded answer")
    assert has_element?(view, "#run-recovery-effect", "same run id")

    assert has_element?(
             view,
             "#run-recovery-unavailable",
             "one explicit checkpoint-backed recovery slice only"
           )

    assert has_element?(view, "#run-resume-pipeline", "Resume From Checkpoint")

    view
    |> element("#run-resume-pipeline")
    |> render_click()

    wait_for_pipeline_status(pipeline_id, "success")

    assert has_element?(view, "#run-current-state", "Completed")
    assert has_element?(view, "#run-recovery-receipt")
    assert has_element?(view, "#run-recovery-receipt-label", "Checkpoint resume started")
    assert has_element?(view, "#run-recovery-receipt-detail", "same run id")

    assert has_element?(
             view,
             "#run-recovery-receipt-known-limit",
             "qualified checkpoint-backed continuity slice on the same run id only"
           )
  end

  defp fail_dot do
    """
    digraph attractor {
      start [shape=Mdiamond]
      task [shape=box, prompt="Task", retry_target="done"]
      done [shape=Msquare]
      start -> task
    }
    """
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

  defp wait_for_questions_to_clear(pipeline_id, attempts \\ 100)

  defp wait_for_questions_to_clear(_pipeline_id, 0),
    do: flunk("expected pending questions to clear")

  defp wait_for_questions_to_clear(pipeline_id, attempts) do
    case AttractorAPI.get_pipeline_questions(pipeline_id) do
      {:ok, %{"questions" => []}} ->
        :ok

      _ ->
        receive do
        after
          20 -> wait_for_questions_to_clear(pipeline_id, attempts - 1)
        end
    end
  end

  defp wait_for_resume_ready(pipeline_id, attempts \\ 100)

  defp wait_for_resume_ready(_pipeline_id, 0), do: flunk("expected checkpoint resume readiness")

  defp wait_for_resume_ready(pipeline_id, attempts) do
    case AttractorAPI.get_pipeline(pipeline_id) do
      {:ok, %{"resume_ready" => true}} ->
        :ok

      _ ->
        receive do
        after
          20 -> wait_for_resume_ready(pipeline_id, attempts - 1)
        end
    end
  end
end
