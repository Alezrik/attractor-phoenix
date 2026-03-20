defmodule AttractorPhoenixWeb.E2E.QATeamAutomationTest do
  use AttractorPhoenixWeb.E2ECase

  @tag :e2e
  test "Noor's API lane covers the selected checkpoint-backed resume contract" do
    base_url = AttractorPhoenixWeb.Endpoint.url()

    output = run_playwright_script!("test/e2e/scripts/noor_api_resume_contract.mjs", base_url)

    assert output =~ "NOOR_API_RESUME_CONTRACT_OK"
    assert output =~ "resume_ready=true"
    assert output =~ "resume_rejected_after_completion=true"
  end

  @tag :e2e
  test "Sable's UI lane covers the canonical operator journey and resume receipt" do
    base_url = AttractorPhoenixWeb.Endpoint.url()

    output = run_playwright_script!("test/e2e/scripts/sable_operator_journey.mjs", base_url)

    assert output =~ "SABLE_OPERATOR_JOURNEY_OK"
    assert output =~ "dashboard_seen=true"
    assert output =~ "resume_receipt_seen=true"
  end

  @tag :e2e
  test "Rhea's performance lane measures the selected resume slice repeatedly" do
    base_url = AttractorPhoenixWeb.Endpoint.url()

    output = run_playwright_script!("test/e2e/scripts/rhea_resume_timing.mjs", base_url)

    assert output =~ "RHEA_RESUME_TIMING_OK"
    assert output =~ "iterations=3"
  end
end
