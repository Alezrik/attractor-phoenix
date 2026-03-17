defmodule AttractorPhoenixWeb.RunLiveTest do
  use AttractorPhoenixWeb.ConnCase

  alias AttractorExPhx.Client, as: AttractorAPI

  import Phoenix.LiveViewTest

  test "run detail shows explicit state and checkpoint truth for failed runs", %{conn: conn} do
    pipeline_id = "run_detail_failed_#{System.unique_integer([:positive])}"

    assert {:ok, %{"pipeline_id" => ^pipeline_id}} =
             AttractorAPI.create_pipeline(success_dot(), %{}, pipeline_id: pipeline_id)

    wait_for_pipeline_status(pipeline_id, "success")
    assert {:ok, %{"status" => "cancelled"}} = AttractorAPI.cancel_pipeline(pipeline_id)
    wait_for_pipeline_status(pipeline_id, "cancelled")

    {:ok, view, _html} = live(conn, ~p"/runs/#{pipeline_id}")

    assert has_element?(view, "#run-state-summary")
    assert has_element?(view, "#run-current-state", "Interrupted")
    assert has_element?(view, "#run-latest-update")
    assert has_element?(view, "#run-checkpoint-summary")
    assert has_element?(view, "#run-checkpoint-detail")
    assert render(view) =~ "checkpoint"
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

    assert has_element?(
             view,
             "a[href='/runs/#{pipeline_id}/debugger?focus=questions']",
             "Open Human-Gate Debugger"
           )
  end

  defp success_dot do
    """
    digraph attractor {
      start [shape=Mdiamond]
      hello [shape=parallelogram, tool_command="echo hello from run live"]
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
