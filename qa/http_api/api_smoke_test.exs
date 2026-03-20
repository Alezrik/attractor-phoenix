defmodule AttractorEx.APISmokeTest do
  use AttractorEx.APISmokeCase, async: false

  @resume_threshold_ms 5_000

  test "GET /pipelines returns an empty list for a fresh server", %{base_url: base_url} do
    response = Req.get!("#{base_url}/pipelines")

    assert response.status == 200
    assert response.body == %{"pipelines" => []}
  end

  test "rejects invalid pipeline submissions with explicit client-visible errors", %{
    base_url: base_url
  } do
    missing_dot =
      Req.post!("#{base_url}/pipelines",
        json: %{"context" => %{"ticket" => "A-2"}}
      )

    assert missing_dot.status == 400
    assert missing_dot.body == %{"error" => "pipeline dot source is required"}

    oversized_dot = String.duplicate("a", 1_000_001)

    oversized =
      Req.post!("#{base_url}/pipelines",
        json: %{"dot" => oversized_dot}
      )

    assert oversized.status == 413
    assert oversized.body["error"] == "request body too large"
    assert oversized.body["max_bytes"] == 1_000_000
  end

  test "repeated reads keep pipeline responses stable across inspection passes", %{
    base_url: base_url
  } do
    pipeline_id = unique_pipeline_id("api_stability")

    create_success_pipeline(base_url, pipeline_id)

    first = Req.get!("#{base_url}/pipelines/#{pipeline_id}")
    second = Req.get!("#{base_url}/pipelines/#{pipeline_id}")

    assert first.status == 200
    assert second.status == 200
    assert response_snapshot(first.body) == response_snapshot(second.body)

    status_response = Req.get!("#{base_url}/status?pipeline_id=#{pipeline_id}")
    assert status_response.status == 200
    assert status_response.body["pipeline_id"] == pipeline_id
    assert status_response.body["status"] == "success"
  end

  test "supports one explicit checkpoint-backed resume for the selected cancelled packet", %{
    base_url: base_url
  } do
    pipeline_id = unique_pipeline_id("api_resume")

    create_selected_resume_packet(base_url, pipeline_id)

    resume = Req.post!("#{base_url}/pipelines/#{pipeline_id}/resume", json: %{})

    assert resume.status == 202
    assert resume.body["pipeline_id"] == pipeline_id
    assert resume.body["status"] == "running"
    assert resume.body["recovery_action"] == "checkpoint_resume"
    assert resume.body["resumed_from_status"] == "cancelled"

    wait_for_pipeline_status(base_url, pipeline_id, "success")

    final = Req.get!("#{base_url}/pipelines/#{pipeline_id}")

    assert final.status == 200
    assert final.body["status"] == "success"
    assert final.body["resume_ready"] == false

    events = Req.get!("#{base_url}/pipelines/#{pipeline_id}/events?stream=false&after=0")

    assert events.status == 200
    assert Enum.any?(events.body["events"], &(&1["type"] == "PipelineResumeStarted"))
    assert Enum.any?(events.body["events"], &(&1["type"] == "PipelineCompleted"))
  end

  test "rejects checkpoint resume when the selected packet contract is not met", %{
    base_url: base_url
  } do
    pipeline_id = unique_pipeline_id("api_resume_reject")

    create_selected_resume_packet(base_url, pipeline_id)

    resume = Req.post!("#{base_url}/pipelines/#{pipeline_id}/resume", json: %{})

    assert resume.status == 202

    second_resume = Req.post!("#{base_url}/pipelines/#{pipeline_id}/resume", json: %{})

    assert second_resume.status == 409
    assert second_resume.body["error"] =~ "selected cancelled packet"
  end

  test "keeps low-concurrency resume attempts responsive for the selected packet", %{
    base_url: base_url
  } do
    for index <- 1..3 do
      pipeline_id = unique_pipeline_id("api_resume_perf_#{index}")

      create_selected_resume_packet(base_url, pipeline_id)

      started_at = System.monotonic_time(:millisecond)
      resume = Req.post!("#{base_url}/pipelines/#{pipeline_id}/resume", json: %{})
      elapsed_ms = System.monotonic_time(:millisecond) - started_at

      assert resume.status == 202
      assert elapsed_ms < @resume_threshold_ms
      wait_for_pipeline_status(base_url, pipeline_id, "success")
    end
  end

  defp create_success_pipeline(base_url, pipeline_id) do
    response =
      Req.post!("#{base_url}/pipelines",
        json: %{
          "dot" => success_dot(),
          "opts" => %{"pipeline_id" => pipeline_id}
        }
      )

    assert response.status == 202
    assert response.body == %{"pipeline_id" => pipeline_id}

    wait_for_pipeline_status(base_url, pipeline_id, "success")
  end

  defp create_selected_resume_packet(base_url, pipeline_id) do
    response =
      Req.post!("#{base_url}/pipelines",
        json: %{
          "dot" => wait_human_dot(),
          "opts" => %{"pipeline_id" => pipeline_id}
        }
      )

    assert response.status == 202
    assert response.body == %{"pipeline_id" => pipeline_id}

    wait_for_pending_questions(base_url, pipeline_id)

    cancel = Req.post!("#{base_url}/pipelines/#{pipeline_id}/cancel", json: %{})
    assert cancel.status == 202
    assert cancel.body == %{"pipeline_id" => pipeline_id, "status" => "cancelled"}

    answer =
      Req.post!("#{base_url}/pipelines/#{pipeline_id}/questions/gate/answer",
        json: %{"answer" => "A"}
      )

    assert answer.status == 202

    wait_for_resume_ready(base_url, pipeline_id)
  end

  defp wait_for_pending_questions(base_url, pipeline_id, attempts \\ 100)

  defp wait_for_pending_questions(_base_url, _pipeline_id, 0) do
    flunk("expected pending questions")
  end

  defp wait_for_pending_questions(base_url, pipeline_id, attempts) do
    case Req.get!("#{base_url}/pipelines/#{pipeline_id}").body do
      %{"pending_questions" => pending} when pending > 0 ->
        :ok

      _ ->
        receive do
        after
          20 -> wait_for_pending_questions(base_url, pipeline_id, attempts - 1)
        end
    end
  end

  defp wait_for_resume_ready(base_url, pipeline_id, attempts \\ 100)

  defp wait_for_resume_ready(_base_url, _pipeline_id, 0) do
    flunk("expected resume readiness")
  end

  defp wait_for_resume_ready(base_url, pipeline_id, attempts) do
    case Req.get!("#{base_url}/pipelines/#{pipeline_id}").body do
      %{"status" => "cancelled", "resume_ready" => true} ->
        :ok

      _ ->
        receive do
        after
          20 -> wait_for_resume_ready(base_url, pipeline_id, attempts - 1)
        end
    end
  end

  defp wait_for_pipeline_status(base_url, pipeline_id, expected_status, attempts \\ 100)

  defp wait_for_pipeline_status(_base_url, _pipeline_id, _expected_status, 0) do
    flunk("expected pipeline status")
  end

  defp wait_for_pipeline_status(base_url, pipeline_id, expected_status, attempts) do
    case Req.get!("#{base_url}/pipelines/#{pipeline_id}").body do
      %{"status" => ^expected_status} ->
        :ok

      _ ->
        receive do
        after
          20 -> wait_for_pipeline_status(base_url, pipeline_id, expected_status, attempts - 1)
        end
    end
  end

  defp response_snapshot(body) when is_map(body) do
    %{
      "status" => body["status"],
      "event_count" => body["event_count"],
      "pending_questions" => body["pending_questions"],
      "has_checkpoint" => body["has_checkpoint"],
      "resume_ready" => body["resume_ready"]
    }
  end

  defp unique_pipeline_id(prefix) do
    "#{prefix}_#{System.unique_integer([:positive])}"
  end

  defp success_dot do
    """
    digraph attractor {
      start [shape=Mdiamond]
      hello [shape=parallelogram, tool_command="echo hello from api smoke"]
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
end
