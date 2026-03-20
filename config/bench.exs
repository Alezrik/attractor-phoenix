import Config

config :attractor_phoenix, AttractorPhoenixWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4003],
  secret_key_base: "r7P/7hFphhmTYpgM4HFRZQBO/3N7ncfNj1jjN5fQGQqgqvJUpYkjuv9JY0/WQm9K",
  server: false

config :swoosh, :api_client, false

config :logger, level: :warning

config :phoenix, :plug_init_mode, :runtime

config :phoenix_live_view,
  enable_expensive_runtime_checks: true,
  colocated_js: [disable_symlink_warning: true]

config :attractor_phoenix, :attractor_http,
  port: 4102,
  ip: {127, 0, 0, 1},
  base_url: "http://127.0.0.1:4102",
  store_root: Path.expand("../tmp/attractor_http_store_bench", __DIR__)

config :attractor_phoenix,
  pipeline_library_path: Path.expand("../tmp/pipeline_library_bench.json", __DIR__),
  llm_setup_path: Path.expand("../tmp/llm_setup_bench.json", __DIR__)
