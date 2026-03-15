defmodule AttractorPhoenixWeb.BenchmarkLive do
  use AttractorPhoenixWeb, :live_view

  alias AttractorPhoenix.Benchmark

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
end
