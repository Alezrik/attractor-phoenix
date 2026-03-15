defmodule AttractorPhoenixWeb.DashboardLiveTest do
  use AttractorPhoenixWeb.ConnCase

  alias AttractorExPhx.Client, as: AttractorAPI

  import Phoenix.LiveViewTest

  test "overview renders run list and filters by status", %{conn: conn} do
    cancelled_id = "dashboard_cancelled_#{System.unique_integer([:positive])}"
    success_id = "dashboard_success_#{System.unique_integer([:positive])}"

    assert {:ok, %{"pipeline_id" => ^cancelled_id}} =
             AttractorAPI.create_pipeline(wait_human_dot(), %{}, pipeline_id: cancelled_id)

    assert {:ok, %{"pipeline_id" => ^success_id}} =
             AttractorAPI.create_pipeline(success_dot(), %{}, pipeline_id: success_id)

    wait_for_questions(cancelled_id)
    assert {:ok, %{"status" => "cancelled"}} = AttractorAPI.cancel_pipeline(cancelled_id)
    wait_for_pipeline_status(cancelled_id, "cancelled")
    wait_for_pipeline_status(success_id, "success")

    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(view, "#dashboard-filter-form")
    assert has_element?(view, "#open-run-#{cancelled_id}")
    assert has_element?(view, "#open-run-#{success_id}")

    html =
      view
      |> element("#dashboard-filter-form")
      |> render_change(%{
        "filters" => %{"status" => "cancelled", "questions" => "all", "search" => ""}
      })

    assert html =~ cancelled_id
    refute html =~ success_id
  end

  test "overview search narrows the run list by pipeline id", %{conn: conn} do
    first_id = "search_alpha_#{System.unique_integer([:positive])}"
    second_id = "search_beta_#{System.unique_integer([:positive])}"

    assert {:ok, %{"pipeline_id" => ^first_id}} =
             AttractorAPI.create_pipeline(success_dot(), %{}, pipeline_id: first_id)

    assert {:ok, %{"pipeline_id" => ^second_id}} =
             AttractorAPI.create_pipeline(success_dot(), %{}, pipeline_id: second_id)

    wait_for_pipeline_status(first_id, "success")
    wait_for_pipeline_status(second_id, "success")

    {:ok, view, _html} = live(conn, ~p"/")

    html =
      view
      |> element("#dashboard-filter-form")
      |> render_change(%{
        "filters" => %{"status" => "all", "questions" => "all", "search" => "alpha"}
      })

    assert html =~ first_id
    refute html =~ second_id
  end

  test "run detail loads directly by deep link and answers wait.human questions", %{conn: conn} do
    pipeline_id = "run_detail_wait_human_#{System.unique_integer([:positive])}"

    assert {:ok, %{"pipeline_id" => ^pipeline_id}} =
             AttractorAPI.create_pipeline(wait_human_dot(), %{}, pipeline_id: pipeline_id)

    wait_for_questions(pipeline_id)

    {:ok, view, _html} = live(conn, ~p"/runs/#{pipeline_id}")

    assert has_element?(view, "#run-detail-page")
    assert has_element?(view, "#answer-form-gate")
    assert has_element?(view, "#answer-form-gate select[name='response[choice]']")

    view
    |> element("#answer-form-gate")
    |> render_submit(%{"question_id" => "gate", "response" => %{"choice" => "A"}})

    wait_for_pipeline_status(pipeline_id, "success")

    refute has_element?(view, "#answer-form-gate")
  end

  test "run detail renders multi-select controls for wait.human metadata", %{conn: conn} do
    pipeline_id = "run_detail_multi_#{System.unique_integer([:positive])}"

    assert {:ok, %{"pipeline_id" => ^pipeline_id}} =
             AttractorAPI.create_pipeline(wait_human_multi_dot(), %{}, pipeline_id: pipeline_id)

    wait_for_questions(pipeline_id)

    {:ok, view, _html} = live(conn, ~p"/runs/#{pipeline_id}")

    assert has_element?(view, "#answer-form-gate select[multiple][name='response[choices][]']")
    assert render(view) =~ "checkbox"
    assert render(view) =~ "optional"
  end

  test "debugger route renders URL-backed filters and the event inspector", %{conn: conn} do
    pipeline_id = "run_debugger_filters_#{System.unique_integer([:positive])}"

    assert {:ok, %{"pipeline_id" => ^pipeline_id}} =
             AttractorAPI.create_pipeline(wait_human_dot(), %{}, pipeline_id: pipeline_id)

    wait_for_questions(pipeline_id)

    {:ok, view, _html} =
      live(conn, ~p"/runs/#{pipeline_id}/debugger?focus=questions&search=Approve")

    assert has_element?(view, "#run-debugger-page")
    assert has_element?(view, "#debugger-filter-form")
    assert has_element?(view, "#debugger-search[value='Approve']")
    assert has_element?(view, "#debugger-focus-filter option[selected][value='questions']")
    assert has_element?(view, "#debugger-timeline")
    assert has_element?(view, "#debugger-event-inspector")
    assert has_element?(view, "#debugger-question-inbox")

    view
    |> element("#debugger-filter-form")
    |> render_change(%{
      "filters" => %{
        "type" => "all",
        "status" => "all",
        "node" => "gate",
        "search" => "",
        "focus" => "questions"
      }
    })

    assert_patch(view, ~p"/runs/#{pipeline_id}/debugger?focus=questions&node=gate")
  end

  test "debugger answers wait.human questions from the inbox", %{conn: conn} do
    pipeline_id = "run_debugger_answer_#{System.unique_integer([:positive])}"

    assert {:ok, %{"pipeline_id" => ^pipeline_id}} =
             AttractorAPI.create_pipeline(wait_human_dot(), %{}, pipeline_id: pipeline_id)

    wait_for_questions(pipeline_id)

    {:ok, view, _html} = live(conn, ~p"/runs/#{pipeline_id}/debugger")

    assert has_element?(view, "#debugger-answer-form-gate")
    assert has_element?(view, "#debugger-context-diff")

    view
    |> element("#debugger-answer-form-gate")
    |> render_submit(%{"question_id" => "gate", "response" => %{"choice" => "A"}})

    wait_for_pipeline_status(pipeline_id, "success")

    refute has_element?(view, "#debugger-answer-form-gate")
  end

  defp success_dot do
    """
    digraph attractor {
      start [shape=Mdiamond]
      hello [shape=parallelogram, tool_command="echo hello from dashboard"]
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

  defp wait_human_multi_dot do
    """
    digraph attractor {
      start [shape=Mdiamond]
      gate [
        shape=hexagon,
        prompt="Pick release actions",
        human.multiple=true,
        human.required=false,
        human.input="checkbox"
      ]
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
