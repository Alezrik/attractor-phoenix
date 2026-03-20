defmodule AttractorPhoenixWeb.FailureReviewLiveTest do
  use AttractorPhoenixWeb.ConnCase

  alias AttractorExPhx.Client, as: AttractorAPI

  import Phoenix.LiveViewTest

  test "failure review loads directly and only shows failed or cancelled runs", %{conn: conn} do
    cancelled_id = "failure_cancelled_#{System.unique_integer([:positive])}"
    failed_id = "failure_failed_#{System.unique_integer([:positive])}"
    success_id = "failure_success_#{System.unique_integer([:positive])}"

    assert {:ok, %{"pipeline_id" => ^cancelled_id}} =
             AttractorAPI.create_pipeline(wait_human_dot(), %{}, pipeline_id: cancelled_id)

    assert {:ok, %{"pipeline_id" => ^failed_id}} =
             AttractorAPI.create_pipeline(fail_dot(), %{}, pipeline_id: failed_id)

    assert {:ok, %{"pipeline_id" => ^success_id}} =
             AttractorAPI.create_pipeline(success_dot(), %{}, pipeline_id: success_id)

    wait_for_questions(cancelled_id)
    assert {:ok, %{"status" => "cancelled"}} = AttractorAPI.cancel_pipeline(cancelled_id)
    wait_for_pipeline_status(cancelled_id, "cancelled")
    wait_for_pipeline_status(failed_id, "fail")
    wait_for_pipeline_status(success_id, "success")

    {:ok, view, _html} = live(conn, ~p"/failures")

    assert has_element?(view, "#failure-review-page")
    assert has_element?(view, "#open-failure-run-#{cancelled_id}")
    assert has_element?(view, "#failure-signal-#{cancelled_id}")

    assert has_element?(
             view,
             "#failure-signal-#{cancelled_id}",
             "Human gate blocks progress"
           )

    assert has_element?(
             view,
             "#open-failure-question-debugger-#{cancelled_id}[href='/runs/#{cancelled_id}/debugger?focus=questions']"
           )

    assert has_element?(
             view,
             "#open-failure-debugger-#{cancelled_id}[href='/runs/#{cancelled_id}/debugger?focus=failures']"
           )

    assert has_element?(
             view,
             "#failure-recovery-owner-#{cancelled_id}",
             "Operator review required"
           )

    assert has_element?(
             view,
             "#failure-recovery-action-#{cancelled_id}",
             "Answer pending human gate"
           )

    assert has_element?(
             view,
             "#failure-recovery-label-#{cancelled_id}",
             "Human gate blocks progress"
           )

    assert has_element?(
             view,
             "#failure-recovery-effect-#{cancelled_id}",
             "does not retry, replay, or resume"
           )

    assert has_element?(
             view,
             "#failure-route-mode-#{cancelled_id}",
             "action-taking route"
           )

    assert has_element?(view, "#open-failure-run-#{failed_id}")
    assert has_element?(view, "#failure-signal-#{failed_id}", "Failure with checkpoint context")

    assert has_element?(
             view,
             "#failure-recovery-next-step-#{failed_id}",
             "Inspect the debugger timeline and checkpoint diff"
           )

    assert has_element?(
             view,
             "#failure-route-mode-#{failed_id}",
             "inspection-first route"
           )

    refute has_element?(view, "#open-failure-run-#{success_id}")
  end

  test "failure review filters by question state and search", %{conn: conn} do
    with_questions_id = "failure_with_questions_#{System.unique_integer([:positive])}"
    clear_questions_id = "failure_clear_#{System.unique_integer([:positive])}"

    assert {:ok, %{"pipeline_id" => ^with_questions_id}} =
             AttractorAPI.create_pipeline(wait_human_dot(), %{}, pipeline_id: with_questions_id)

    assert {:ok, %{"pipeline_id" => ^clear_questions_id}} =
             AttractorAPI.create_pipeline(success_dot(), %{}, pipeline_id: clear_questions_id)

    wait_for_questions(with_questions_id)
    assert {:ok, %{"status" => "cancelled"}} = AttractorAPI.cancel_pipeline(with_questions_id)
    wait_for_pipeline_status(with_questions_id, "cancelled")

    wait_for_pipeline_status(clear_questions_id, "success")
    assert {:ok, %{"status" => "cancelled"}} = AttractorAPI.cancel_pipeline(clear_questions_id)
    wait_for_pipeline_status(clear_questions_id, "cancelled")

    {:ok, view, _html} = live(conn, ~p"/failures")

    html =
      view
      |> element("#failure-review-filter-form")
      |> render_change(%{
        "filters" => %{
          "status" => "cancelled",
          "questions" => "open",
          "search" => "with_questions"
        }
      })

    assert html =~ with_questions_id
    refute html =~ clear_questions_id
    assert_patch(view, ~p"/failures?questions=open&search=with_questions&status=cancelled")
  end

  test "failure review surfaces interruption signals for cancelled runs without open questions",
       %{
         conn: conn
       } do
    cancelled_id = "failure_interrupted_#{System.unique_integer([:positive])}"

    assert {:ok, %{"pipeline_id" => ^cancelled_id}} =
             AttractorAPI.create_pipeline(success_dot(), %{}, pipeline_id: cancelled_id)

    wait_for_pipeline_status(cancelled_id, "success")
    assert {:ok, %{"status" => "cancelled"}} = AttractorAPI.cancel_pipeline(cancelled_id)
    wait_for_pipeline_status(cancelled_id, "cancelled")

    {:ok, view, _html} = live(conn, ~p"/failures?status=cancelled&questions=clear")

    assert has_element?(view, "#failure-signal-#{cancelled_id}", "Interrupted")

    assert has_element?(
             view,
             "#failure-recovery-label-#{cancelled_id}",
             "Interrupted with checkpoint context"
           )
  end

  test "failure review route can clear a cancelled run's pending human gate without implying resume",
       %{conn: conn} do
    pipeline_id = "failure_route_answer_#{System.unique_integer([:positive])}"

    assert {:ok, %{"pipeline_id" => ^pipeline_id}} =
             AttractorAPI.create_pipeline(wait_human_dot(), %{}, pipeline_id: pipeline_id)

    wait_for_questions(pipeline_id)
    assert {:ok, %{"status" => "cancelled"}} = AttractorAPI.cancel_pipeline(pipeline_id)
    wait_for_pipeline_status(pipeline_id, "cancelled")

    {:ok, failure_view, _html} = live(conn, ~p"/failures?questions=open&search=#{pipeline_id}")

    assert has_element?(
             failure_view,
             "#open-failure-question-debugger-#{pipeline_id}[href='/runs/#{pipeline_id}/debugger?focus=questions']"
           )

    {:ok, debugger_view, _html} = live(conn, ~p"/runs/#{pipeline_id}/debugger?focus=questions")

    debugger_view
    |> element("#debugger-answer-form-gate")
    |> render_submit(%{"question_id" => "gate", "response" => %{"choice" => "A"}})

    wait_for_questions_to_clear(pipeline_id)
    wait_for_failure_queue_question_clear(pipeline_id)

    refute has_element?(debugger_view, "#debugger-answer-form-gate")
    assert has_element?(debugger_view, "#debugger-run-state", "Interrupted")
    assert has_element?(debugger_view, "#debugger-human-gate-resolution")

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

    {:ok, cleared_failure_view, _html} =
      live(conn, ~p"/failures?questions=open&search=#{pipeline_id}")

    assert has_element?(
             cleared_failure_view,
             "#failure-review-empty",
             "No runs currently need failure review"
           )

    assert render(cleared_failure_view) =~ "0 runs shown"
  end

  test "dashboard review-failures controls navigate to the dedicated route", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(view, "#shell-filter-fail-runs[href='/failures']")
    assert has_element?(view, "#filter-fail-runs[href='/failures']")
  end

  defp success_dot do
    """
    digraph attractor {
      start [shape=Mdiamond]
      hello [shape=parallelogram, tool_command="echo hello from failure review"]
      done [shape=Msquare]
      start -> hello
      hello -> done
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

  defp wait_for_failure_queue_question_clear(pipeline_id, attempts \\ 100)

  defp wait_for_failure_queue_question_clear(_pipeline_id, 0) do
    flunk("expected failure queue question summary to clear")
  end

  defp wait_for_failure_queue_question_clear(pipeline_id, attempts) do
    case AttractorAPI.list_pipelines() do
      {:ok, %{"pipelines" => pipelines}} ->
        case Enum.find(pipelines, &(&1["pipeline_id"] == pipeline_id)) do
          %{"pending_questions" => 0} ->
            :ok

          _ ->
            receive do
            after
              20 -> wait_for_failure_queue_question_clear(pipeline_id, attempts - 1)
            end
        end

      _ ->
        receive do
        after
          20 -> wait_for_failure_queue_question_clear(pipeline_id, attempts - 1)
        end
    end
  end
end
