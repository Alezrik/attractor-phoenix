defmodule AttractorPhoenixWeb.E2E.Smoke.HelloWorldTest do
  use AttractorPhoenixWeb.E2ECase

  @tag :e2e
  test "opens the operator dashboard home page" do
    home_url = AttractorPhoenixWeb.Endpoint.url() <> "/"
    output = run_playwright_script!("test/e2e/scripts/open_home_page.mjs", home_url)

    assert output =~ "Opened #{home_url}"
  end
end
