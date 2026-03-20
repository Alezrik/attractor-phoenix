Mix.shell().info("Running focused benchmark script: bench/hello_world.exs")

Benchee.run(
  %{
    "hello_world_string" => fn name ->
      "Hello World, #{name}!"
    end
  },
  inputs: %{"library_smoke_check" => "AttractorPhoenix"},
  time: 1,
  warmup: 0.5,
  memory_time: 0.2,
  print: [fast_warning: false]
)
