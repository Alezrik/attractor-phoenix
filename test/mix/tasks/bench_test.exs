defmodule Mix.Tasks.BenchTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  setup do
    original_cwd = File.cwd!()
    tmp_dir = Path.join(System.tmp_dir!(), "mix-bench-#{System.unique_integer([:positive])}")
    File.mkdir_p!(Path.join(tmp_dir, "bench"))

    on_exit(fn ->
      File.cd!(original_cwd)
      File.rm_rf(tmp_dir)
      Mix.Task.clear()
    end)

    %{tmp_dir: tmp_dir}
  end

  test "runs the default hello world benchmark script", %{tmp_dir: tmp_dir} do
    write_script(Path.join([tmp_dir, "bench", "hello_world.exs"]), "default benchmark")

    output =
      capture_io(fn ->
        in_tmp_dir(tmp_dir, fn ->
          Mix.Task.reenable("bench")
          Mix.Tasks.Bench.run([])
        end)
      end)

    assert output =~ "default benchmark"
  end

  test "runs an explicitly selected benchmark script", %{tmp_dir: tmp_dir} do
    write_script(Path.join([tmp_dir, "bench", "custom.exs"]), "custom benchmark")

    output =
      capture_io(fn ->
        in_tmp_dir(tmp_dir, fn ->
          Mix.Task.reenable("bench")
          Mix.Tasks.Bench.run(["bench/custom.exs"])
        end)
      end)

    assert output =~ "custom benchmark"
  end

  test "raises when the selected benchmark script does not exist", %{tmp_dir: tmp_dir} do
    assert_raise Mix.Error, ~r/Benchmark script not found/, fn ->
      in_tmp_dir(tmp_dir, fn ->
        Mix.Task.reenable("bench")
        Mix.Tasks.Bench.run([])
      end)
    end
  end

  defp in_tmp_dir(tmp_dir, fun) do
    previous = File.cwd!()

    try do
      File.cd!(tmp_dir)
      fun.()
    after
      File.cd!(previous)
    end
  end

  defp write_script(path, message) do
    File.write!(path, "Mix.shell().info(#{inspect(message)})\n")
  end
end
