# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :attractor_phoenix,
  generators: [timestamp_type: :utc_datetime],
  pipeline_library_path: Path.expand("../tmp/pipeline_library.json", __DIR__),
  attractor_pubsub_bridge: AttractorPhoenix.AttractorPubSubBridge,
  attractor_http: [
    port: 4041,
    ip: {127, 0, 0, 1},
    base_url: "http://127.0.0.1:4041",
    manager: AttractorPhoenix.AttractorHTTP.Manager,
    registry: AttractorPhoenix.AttractorHTTP.Registry
  ]

# Configure the endpoint
config :attractor_phoenix, AttractorPhoenixWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: AttractorPhoenixWeb.ErrorHTML, json: AttractorPhoenixWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: AttractorPhoenix.PubSub,
  live_view: [signing_salt: "k3howbik"]

# Configure the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :attractor_phoenix, AttractorPhoenix.Mailer, adapter: Swoosh.Adapters.Local

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  attractor_phoenix: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.12",
  attractor_phoenix: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
