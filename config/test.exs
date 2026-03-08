import Config

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :attractor_phoenix, AttractorPhoenixWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "kYoCrewZI2DJ/xNdrlpYS7VRO7ZNR3mBge2zdUhZDOQmnFDHKRXMfggysXYL6VQE",
  server: false

# In test we don't send emails
config :attractor_phoenix, AttractorPhoenix.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true,
  colocated_js: [disable_symlink_warning: true]

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true

config :junit_formatter,
  report_dir: "test-results",
  report_file: "junit.xml",
  automatic_create_dir?: true

config :attractor_phoenix, :attractor_http,
  port: 4101,
  ip: {127, 0, 0, 1},
  base_url: "http://127.0.0.1:4101"

config :attractor_phoenix,
  pipeline_library_path: Path.expand("../tmp/pipeline_library_test.json", __DIR__)
