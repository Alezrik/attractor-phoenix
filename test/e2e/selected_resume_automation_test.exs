defmodule AttractorPhoenixWeb.E2E.SelectedResumeAutomationTest do
  use AttractorPhoenixWeb.E2ECase

  @tag :e2e
  test "selected checkpoint-backed resume contract is enforced through the control plane" do
    base_url = AttractorPhoenixWeb.Endpoint.url()

    output = run_playwright_script!("test/e2e/scripts/selected_resume_api_contract.mjs", base_url)

    assert output =~ "NOOR_API_RESUME_CONTRACT_OK"
    assert output =~ "refusal_state=refused"
    assert output =~ "availability_state=available"
    assert output =~ "post_resume_state=refused"
    assert output =~ "resume_rejected_after_completion=true"
  end

  @tag :e2e
  test "selected operator journey exposes resume receipt through the UI" do
    base_url = AttractorPhoenixWeb.Endpoint.url()

    output =
      run_playwright_script!("test/e2e/scripts/selected_resume_operator_journey.mjs", base_url)

    assert output =~ "SABLE_OPERATOR_JOURNEY_OK"
    assert output =~ "refusal_seen=true"
    assert output =~ "availability_seen=true"
    assert output =~ "qualified_continuity_seen=true"
  end

  @tag :e2e
  test "selected resume slice timing is measured repeatedly" do
    base_url = AttractorPhoenixWeb.Endpoint.url()

    output = run_playwright_script!("test/e2e/scripts/selected_resume_timing.mjs", base_url)

    assert output =~ "RHEA_RESUME_TIMING_OK"
    assert output =~ "iterations=3"
    assert output =~ "max_refusal_ms="
    assert output =~ "max_availability_ms="
    assert output =~ "max_receipt_ms="
  end
end
