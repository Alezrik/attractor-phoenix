defmodule AttractorPhoenix.TrustProof do
  @moduledoc """
  Shared proof-packet shaping for setup and benchmark trust surfaces.
  """

  @owner "Marcus Flint"
  @benchmark_scope "month-1 setup and benchmark trust surfaces"
  @provider_scope "month-1 setup and benchmark trust surfaces"
  @provider_limit "the setup surface shows current configuration state only; latency, cost, quality, and release-grade provider tradeoffs are not yet proven here"
  @benchmark_limit "durable runtime leadership, debugger-grade operator proof, and broader benchmark leadership are not yet proven here"

  @type proof_record :: map()

  @spec benchmark_record(map()) :: proof_record()
  def benchmark_record(benchmark) when is_map(benchmark) do
    status = if benchmark.leadership_ready?, do: "ready", else: "partial"

    %{
      surface: "benchmark",
      scope: @benchmark_scope,
      subject: "current leadership benchmark posture",
      status: status,
      claim_level: status,
      confidence_basis:
        "weighted benchmark summary plus published conformance scoreboard and verification commands",
      known_limits: @benchmark_limit,
      proof_artifact:
        "AttractorPhoenix.Benchmark.summary() and AttractorPhoenix.Conformance.summary()",
      owner: @owner,
      timestamp: Date.utc_today() |> Date.to_iso8601(),
      next_action:
        "raise blocked leadership criteria with executable proof before broadening benchmark claims",
      benchmark_set: "month-1 leadership benchmark",
      score: "#{benchmark.composite_score} / 5.0 weighted composite",
      comparison_set: Enum.join(benchmark.reference_set, ", ")
    }
  end

  @spec provider_health_record(map()) :: proof_record()
  def provider_health_record(settings) when is_map(settings) do
    status = provider_status(settings)
    configured_entries = configured_entries(settings)
    configured_names = Enum.map_join(configured_entries, ", ", &provider_label/1)

    %{
      surface: "provider health",
      scope: @provider_scope,
      subject: "configured provider set",
      status: status,
      claim_level: status,
      confidence_basis: provider_confidence_basis(status, settings),
      known_limits: @provider_limit,
      proof_artifact: "AttractorPhoenix.LLMSetup.get_settings()",
      owner: @owner,
      timestamp: provider_timestamp(settings),
      next_action:
        "refresh provider inventory and keep latency, cost, and quality claims inside benchmark-backed evidence",
      provider:
        if(configured_names == "",
          do: "configured provider set (none yet)",
          else: configured_names
        ),
      readiness: provider_readiness_label(status, settings),
      latency_cost_quality_tradeoff:
        "latency, cost, and quality tradeoffs remain documentation-backed until deeper benchmark evidence exists"
    }
  end

  @spec support_phrase(proof_record()) :: String.t()
  def support_phrase(%{claim_level: claim_level})
      when claim_level in ["ready", "fixed", "improved"],
      do: "supported by"

  def support_phrase(%{claim_level: claim_level}) when claim_level in ["partial", "blocked"],
    do: "partially supported by"

  def support_phrase(%{claim_level: "unproven"}), do: "not yet proven"

  def support_phrase(_record), do: "partially supported by"

  defp provider_status(settings) do
    configured_entries = configured_entries(settings)

    cond do
      configured_entries == [] ->
        "unproven"

      Enum.any?(configured_entries, &provider_blocked?/1) ->
        "blocked"

      settings.default_provider && settings.default_model &&
          Enum.all?(configured_entries, &provider_ready?/1) ->
        "ready"

      true ->
        "partial"
    end
  end

  defp configured_entries(settings) do
    settings
    |> Map.get(:providers, %{})
    |> Map.values()
    |> Enum.filter(&provider_configured?/1)
  end

  defp provider_configured?(entry) do
    String.trim(entry.api_key) != "" or entry.mode == "cli"
  end

  defp provider_ready?(entry) do
    entry.last_error == nil and entry.models != [] and not is_nil(entry.last_synced_at)
  end

  defp provider_blocked?(entry) do
    entry.last_error != nil
  end

  defp provider_confidence_basis("ready", settings) do
    "#{length(configured_entries(settings))} configured provider(s) show discovered inventory and a default generation route in the persisted setup snapshot"
  end

  defp provider_confidence_basis("blocked", settings) do
    "#{length(configured_entries(settings))} configured provider(s) are present, but at least one provider currently reports a refresh error in the persisted setup snapshot"
  end

  defp provider_confidence_basis("partial", settings) do
    "#{length(configured_entries(settings))} configured provider(s) exist, but readiness is still incomplete in the persisted setup snapshot"
  end

  defp provider_confidence_basis("unproven", _settings) do
    "no configured provider or discovered model inventory is present in the persisted setup snapshot"
  end

  defp provider_readiness_label("ready", settings) do
    "#{length(configured_entries(settings))} configured provider(s) ready for default routing"
  end

  defp provider_readiness_label("blocked", _settings),
    do: "at least one configured provider is blocked"

  defp provider_readiness_label("partial", _settings),
    do: "configured provider set is only partially ready"

  defp provider_readiness_label("unproven", _settings), do: "provider readiness not yet proven"

  defp provider_timestamp(settings) do
    settings
    |> Map.get(:providers, %{})
    |> Map.values()
    |> Enum.map(& &1.last_synced_at)
    |> Enum.reject(&is_nil/1)
    |> case do
      [] -> Date.utc_today() |> Date.to_iso8601()
      timestamps -> Enum.max(timestamps)
    end
  end

  defp provider_label(entry) do
    entry.id
    |> String.split("_")
    |> Enum.map_join(" ", &String.capitalize/1)
  end
end
