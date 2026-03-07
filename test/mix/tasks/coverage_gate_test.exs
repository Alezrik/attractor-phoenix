defmodule Mix.Tasks.Coverage.GateTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  setup do
    original_cwd = File.cwd!()
    tmp_dir = Path.join(System.tmp_dir!(), "coverage-gate-#{System.unique_integer([:positive])}")
    File.mkdir_p!(Path.join(tmp_dir, "cover"))

    on_exit(fn ->
      File.cd!(original_cwd)
      File.rm_rf(tmp_dir)
      Mix.Task.clear()
    end)

    %{tmp_dir: tmp_dir}
  end

  test "prints a success message when coverage is above the minimum", %{tmp_dir: tmp_dir} do
    write_coveralls_config(tmp_dir, 75)
    write_excoveralls_report(tmp_dir, [[1, 1, 1, 1, 0, nil]])

    output =
      capture_io(fn ->
        in_tmp_dir(tmp_dir, fn ->
          Mix.Task.reenable("coverage.gate")
          Mix.Tasks.Coverage.Gate.run([])
        end)
      end)

    assert output =~ "Coverage gate passed: 80.0% >= 75.0%"
  end

  test "raises when coverage is below the configured minimum", %{tmp_dir: tmp_dir} do
    write_coveralls_config(tmp_dir, 90)
    write_excoveralls_report(tmp_dir, [[1, 0, nil]])

    assert_raise Mix.Error, ~r/Expected coverage at least 90.0%, got 50.0%/, fn ->
      in_tmp_dir(tmp_dir, fn ->
        Mix.Task.reenable("coverage.gate")
        Mix.Tasks.Coverage.Gate.run([])
      end)
    end
  end

  test "accepts coverage equal to the configured minimum", %{tmp_dir: tmp_dir} do
    write_coveralls_config(tmp_dir, 75)
    write_excoveralls_report(tmp_dir, [[1, 1, 1, 0, nil]])

    output =
      capture_io(fn ->
        in_tmp_dir(tmp_dir, fn ->
          Mix.Task.reenable("coverage.gate")
          Mix.Tasks.Coverage.Gate.run([])
        end)
      end)

    assert output =~ "Coverage gate passed: 75.0% >= 75.0%"
  end

  test "raises when minimum_coverage is missing", %{tmp_dir: tmp_dir} do
    File.write!(Path.join(tmp_dir, "coveralls.json"), Jason.encode!(%{"coverage_options" => %{}}))
    write_excoveralls_report(tmp_dir, [[1]])

    assert_raise Mix.Error, ~r/Missing coverage_options.minimum_coverage/, fn ->
      in_tmp_dir(tmp_dir, fn ->
        Mix.Task.reenable("coverage.gate")
        Mix.Tasks.Coverage.Gate.run([])
      end)
    end
  end

  test "accepts float minimum coverage values when actual coverage is higher", %{tmp_dir: tmp_dir} do
    write_coveralls_config(tmp_dir, 75.0)
    write_excoveralls_report(tmp_dir, [[1, 1, 1, 1, 0, nil]])

    output =
      capture_io(fn ->
        in_tmp_dir(tmp_dir, fn ->
          Mix.Task.reenable("coverage.gate")
          Mix.Tasks.Coverage.Gate.run([])
        end)
      end)

    assert output =~ "Coverage gate passed: 80.0% >= 75.0%"
  end

  test "raises when minimum_coverage has an invalid type", %{tmp_dir: tmp_dir} do
    File.write!(
      Path.join(tmp_dir, "coveralls.json"),
      Jason.encode!(%{"coverage_options" => %{"minimum_coverage" => "ninety"}})
    )

    write_excoveralls_report(tmp_dir, [[1]])

    assert_raise Mix.Error, ~r/Invalid minimum_coverage/, fn ->
      in_tmp_dir(tmp_dir, fn ->
        Mix.Task.reenable("coverage.gate")
        Mix.Tasks.Coverage.Gate.run([])
      end)
    end
  end

  test "raises when the report has no relevant lines", %{tmp_dir: tmp_dir} do
    write_coveralls_config(tmp_dir, 90)
    write_excoveralls_report(tmp_dir, [[nil, nil]])

    assert_raise Mix.Error, ~r/does not contain any relevant lines/, fn ->
      in_tmp_dir(tmp_dir, fn ->
        Mix.Task.reenable("coverage.gate")
        Mix.Tasks.Coverage.Gate.run([])
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

  defp write_coveralls_config(tmp_dir, minimum_coverage) do
    File.write!(
      Path.join(tmp_dir, "coveralls.json"),
      Jason.encode!(%{"coverage_options" => %{"minimum_coverage" => minimum_coverage}})
    )
  end

  defp write_excoveralls_report(tmp_dir, coverage_rows) do
    source_files =
      Enum.with_index(coverage_rows, fn coverage, index ->
        %{"name" => "lib/example_#{index}.ex", "source" => "", "coverage" => coverage}
      end)

    File.write!(
      Path.join([tmp_dir, "cover", "excoveralls.json"]),
      Jason.encode!(%{"source_files" => source_files})
    )
  end
end
