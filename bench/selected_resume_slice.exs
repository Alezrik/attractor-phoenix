Mix.shell().info("Running focused benchmark script: bench/selected_resume_slice.exs")

{:ok, _started} = Application.ensure_all_started(:attractor_phoenix)

defmodule Bench.SelectedResumeSlice do
  def run do
    Benchee.run(
      %{
        "selected_resume_slice_end_to_end" => fn _input ->
          run_selected_resume_slice()
        end
      },
      inputs: %{"admitted_packet" => :packet},
      time: 1,
      warmup: 0.5,
      memory_time: 0.2,
      print: [fast_warning: false]
    )
  end

  defp run_selected_resume_slice do
    pipeline_id = unique_pipeline_id()
    logs_root = unique_logs_root(pipeline_id)

    expect_ok!(
      AttractorExPhx.Client.create_pipeline(selected_resume_dot(), %{},
        pipeline_id: pipeline_id,
        logs_root: logs_root
      ),
      "create pipeline"
    )

    wait_for_questions(pipeline_id)

    expect_ok!(AttractorExPhx.Client.cancel_pipeline(pipeline_id), "cancel pipeline")
    wait_for_status(pipeline_id, "cancelled")

    expect_ok!(
      AttractorExPhx.Client.answer_question(pipeline_id, "gate", "A"),
      "answer question"
    )

    wait_for_resume_ready(pipeline_id)

    expect_ok!(AttractorExPhx.Client.resume_pipeline(pipeline_id), "resume pipeline")
    wait_for_status(pipeline_id, "success")
  end

  defp selected_resume_dot do
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

  defp wait_for_questions(_pipeline_id, 0),
    do: raise("expected pending questions for selected resume slice")

  defp wait_for_questions(pipeline_id, attempts) do
    case AttractorExPhx.Client.get_pipeline_questions(pipeline_id) do
      {:ok, %{"questions" => [_ | _]}} ->
        :ok

      _ ->
        sleep_or_retry(fn -> wait_for_questions(pipeline_id, attempts - 1) end)
    end
  end

  defp wait_for_resume_ready(pipeline_id, attempts \\ 100)

  defp wait_for_resume_ready(_pipeline_id, 0),
    do: raise("expected resume_ready for selected packet")

  defp wait_for_resume_ready(pipeline_id, attempts) do
    case AttractorExPhx.Client.get_pipeline(pipeline_id) do
      {:ok, %{"resume_ready" => true}} ->
        :ok

      _ ->
        sleep_or_retry(fn -> wait_for_resume_ready(pipeline_id, attempts - 1) end)
    end
  end

  defp wait_for_status(pipeline_id, status, attempts \\ 100)

  defp wait_for_status(_pipeline_id, _status, 0), do: raise("expected pipeline status")

  defp wait_for_status(pipeline_id, status, attempts) do
    case AttractorExPhx.Client.get_pipeline(pipeline_id) do
      {:ok, %{"status" => ^status}} ->
        :ok

      _ ->
        sleep_or_retry(fn -> wait_for_status(pipeline_id, status, attempts - 1) end)
    end
  end

  defp sleep_or_retry(fun) do
    receive do
    after
      20 -> fun.()
    end
  end

  defp expect_ok!({:ok, value}, _label), do: value

  defp expect_ok!({:error, reason}, label) do
    raise "#{label} failed: #{reason}"
  end

  defp unique_pipeline_id do
    "bench_resume_" <> Integer.to_string(System.unique_integer([:positive]))
  end

  defp unique_logs_root(pipeline_id) do
    Path.join([System.tmp_dir!(), "attractor_resume_bench", pipeline_id])
  end
end

Bench.SelectedResumeSlice.run()
