defmodule AttractorPhoenixWeb.BenchmarkLive do
  use AttractorPhoenixWeb, :live_view

  alias AttractorPhoenix.Benchmark
  alias AttractorPhoenix.TrustProof

  @impl true
  def mount(_params, _session, socket) do
    summary = Benchmark.summary()

    {:ok,
     assign(socket,
       page_title: "Benchmark",
       benchmark: summary
     )}
  end

  defp score_width(score), do: "width: #{Float.round(score / 5 * 100, 1)}%"

  defp weight_percent(weight), do: "#{round(weight * 100)}%"

  defp score_tone(score) when score >= 4.0, do: "bg-success"
  defp score_tone(score) when score >= 3.0, do: "bg-info"
  defp score_tone(score) when score >= 2.0, do: "bg-warning"
  defp score_tone(_score), do: "bg-error"

  defp completion_ratio(completed, total), do: "#{completed}/#{total}"

  defp premium_feature_tone(status) when status in ["Foundation exists", "Partially enabled"],
    do: "bg-info/12 text-info"

  defp premium_feature_tone(status) when status in ["Design-ready"],
    do: "bg-warning/12 text-warning"

  defp premium_feature_tone(_status), do: "bg-base-200 text-base-content/70"

  defp leadership_status_tone(true), do: "bg-success/12 text-success"
  defp leadership_status_tone(false), do: "bg-warning/12 text-warning"

  defp proof_status_tone(status) when status in ["ready", "fixed"],
    do: "bg-success/12 text-success"

  defp proof_status_tone("improved"), do: "bg-info/12 text-info"
  defp proof_status_tone("partial"), do: "bg-warning/12 text-warning"
  defp proof_status_tone("blocked"), do: "bg-error/12 text-error"
  defp proof_status_tone("unproven"), do: "bg-base-200 text-base-content/70"
  defp proof_status_tone(_status), do: "bg-base-200 text-base-content/70"

  defp proof_fields(record) do
    [
      {"Surface", record.surface},
      {"Scope", record.scope},
      {"Subject", record.subject},
      {"Status", record.status},
      {"Claim level", record.claim_level},
      {"Confidence basis", record.confidence_basis},
      {"Proof artifact", record.proof_artifact},
      {"Owner", record.owner},
      {"Timestamp", record.timestamp},
      {"Next action", record.next_action},
      {"Benchmark set", record.benchmark_set},
      {"Score", record.score},
      {"Comparison set", record.comparison_set}
    ]
  end

  defp support_phrase(record), do: TrustProof.support_phrase(record)

  defp blocked_criteria(benchmark) do
    Enum.reject(benchmark.leadership_criteria, & &1.met?)
  end

  defp top_dimension(benchmark) do
    Enum.max_by(benchmark.dimensions, & &1.score)
  end

  defp weakest_dimension(benchmark) do
    Enum.min_by(benchmark.dimensions, & &1.score)
  end
end
