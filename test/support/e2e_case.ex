defmodule AttractorPhoenixWeb.E2ECase do
  @moduledoc false

  use ExUnit.CaseTemplate

  using do
    quote do
      import AttractorPhoenixWeb.E2ECase
    end
  end

  def run_playwright_script!(script_path, url) do
    {output, status} =
      System.cmd(
        "node",
        [script_path, url],
        stderr_to_stdout: true
      )

    if status != 0 do
      flunk("""
      Playwright smoke script failed with exit code #{status}

      #{output}
      """)
    end

    output
  end
end
