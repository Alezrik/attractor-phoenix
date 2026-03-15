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
end
