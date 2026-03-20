e2e_enabled? = System.get_env("ATTRACTOR_PHOENIX_E2E") in ~w(1 true t yes)

ExUnit.configure(
  formatters: [JUnitFormatter, ExUnit.CLIFormatter],
  exclude: if(e2e_enabled?, do: [], else: [e2e: true])
)

ExUnit.start()

if e2e_enabled? do
  {:ok, _pid} =
    Bandit.start_link(
      plug: AttractorPhoenixWeb.Endpoint,
      scheme: :http,
      ip: {127, 0, 0, 1},
      port: 4002,
      startup_log: false
    )
end
