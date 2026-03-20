defmodule AttractorEx.APISmokeCase do
  @moduledoc false

  use ExUnit.CaseTemplate

  alias AttractorEx.HTTP.Manager

  using do
    quote do
      import AttractorEx.APISmokeCase
    end
  end

  setup do
    manager = AttractorEx.APISmokeManager
    registry = AttractorEx.APISmokeRegistry

    store_root =
      Path.join(
        System.tmp_dir!(),
        "attractor_api_smoke_store_#{System.unique_integer([:positive])}"
      )

    start_supervised!({Manager, name: manager, store_root: store_root})
    start_supervised!({Registry, keys: :duplicate, name: registry})

    bandit =
      start_supervised!(
        {Bandit,
         plug: {AttractorEx.HTTP.Router, manager: manager, registry: registry},
         scheme: :http,
         ip: {127, 0, 0, 1},
         port: 0,
         startup_log: false}
      )

    {:ok, {_ip, port}} = ThousandIsland.listener_info(bandit)

    %{base_url: "http://127.0.0.1:#{port}"}
  end
end
