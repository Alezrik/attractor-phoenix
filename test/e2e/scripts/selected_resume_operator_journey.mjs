import { chromium } from "../../../assets/node_modules/playwright/index.mjs";

const baseUrl = process.argv[2];
const apiBaseUrl = "http://127.0.0.1:4101";

if (!baseUrl) {
  console.error("Missing base URL argument.");
  process.exit(1);
}

const dot = `digraph attractor {
  start [shape=Mdiamond]
  gate [shape=hexagon, prompt="Approve release?", human.timeout="5s"]
  done [shape=Msquare]
  retry [shape=box, prompt="Retry release"]
  start -> gate
  gate -> done [label="[A] Approve"]
  gate -> retry [label="[R] Retry"]
  retry -> done
}`;

const pipelineId = `sable_ui_journey_${Date.now()}`;
const headers = { "content-type": "application/json" };

async function jsonRequest(path, init = {}) {
  const response = await fetch(`${apiBaseUrl}${path}`, {
    ...init,
    headers: { ...headers, ...(init.headers || {}) }
  });

  const text = await response.text();
  let body;

  try {
    body = text ? JSON.parse(text) : {};
  } catch (error) {
    throw new Error(`Expected JSON from ${path}, got: ${text}`);
  }

  return { response, body };
}

async function waitFor(predicate, label, maxAttempts = 100) {
  for (let attempt = 0; attempt < maxAttempts; attempt += 1) {
    const value = await predicate();
    if (value) return value;
    await new Promise((resolve) => setTimeout(resolve, 100));
  }

  throw new Error(`Timed out waiting for ${label}`);
}

const browser = await chromium.launch();

try {
  const { response: createResponse } = await jsonRequest("/pipelines", {
    method: "POST",
    body: JSON.stringify({ dot, opts: { pipeline_id: pipelineId } })
  });

  if (createResponse.status !== 202) {
    throw new Error(`Expected pipeline creation to return 202, got ${createResponse.status}`);
  }

  await waitFor(async () => {
    const { body } = await jsonRequest(`/pipelines/${pipelineId}/questions`);
    return body.questions && body.questions.length > 0 ? body.questions : null;
  }, "pending questions");

  const { response: cancelResponse } = await jsonRequest(`/pipelines/${pipelineId}/cancel`, {
    method: "POST",
    body: JSON.stringify({})
  });

  if (cancelResponse.status !== 202) {
    throw new Error(`Expected cancel to return 202, got ${cancelResponse.status}`);
  }

  await waitFor(async () => {
    const { body } = await jsonRequest(`/pipelines/${pipelineId}`);
    return body.status === "cancelled" ? body : null;
  }, "pipeline to cancel");

  const page = await browser.newPage();
  await page.goto(`${baseUrl}/runs/${pipelineId}`, { waitUntil: "networkidle" });

  await page.locator("#answer-form-gate").waitFor({ state: "visible" });
  const runGateOwner = await page.locator("#run-human-gate-owner").textContent();
  if (!runGateOwner || !runGateOwner.includes("Operator review required")) {
    throw new Error(`Missing run detail gate owner text: ${runGateOwner}`);
  }

  const runRefusalDetail = await page.locator("#run-recovery-detail").textContent();
  if (
    !runRefusalDetail ||
    !runRefusalDetail.includes("checkpoint resume stays blocked") ||
    !runRefusalDetail.includes("human gate is fully cleared")
  ) {
    throw new Error(`Missing pre-cancel refusal guidance on run detail: ${runRefusalDetail}`);
  }

  await page.goto(`${baseUrl}/failures?questions=open&search=${pipelineId}`, {
    waitUntil: "networkidle"
  });

  const failureRun = page.locator(`#open-failure-question-debugger-${pipelineId}`);
  await failureRun.waitFor({ state: "visible" });

  const failureEffect = await page.locator(`#failure-recovery-effect-${pipelineId}`).textContent();
  if (!failureEffect || !failureEffect.includes("does not retry, replay, or resume")) {
    throw new Error(`Missing failure review known-limit text: ${failureEffect}`);
  }

  const failureRefusalDetail = await page
    .locator(`#failure-recovery-detail-${pipelineId}`)
    .textContent();
  if (
    !failureRefusalDetail ||
    !failureRefusalDetail.includes("checkpoint resume stays blocked") ||
    !failureRefusalDetail.includes("human gate is fully cleared")
  ) {
    throw new Error(`Missing explicit refusal boundary on failure review: ${failureRefusalDetail}`);
  }

  await page.goto(`${baseUrl}/runs/${pipelineId}/debugger?focus=questions`, {
    waitUntil: "networkidle"
  });

  const answerForm = page.locator("#debugger-answer-form-gate");
  await answerForm.waitFor({ state: "visible" });

  await answerForm.locator("select[name='response[choice]']").selectOption("A");
  await answerForm.locator("button[type='submit']").click();

  await waitFor(async () => {
    const { body } = await jsonRequest(`/pipelines/${pipelineId}`);
    return body.resume_ready === true ? body : null;
  }, "resume readiness");

  await page.goto(`${baseUrl}/runs/${pipelineId}`, { waitUntil: "networkidle" });

  const resumeButton = page.locator("#run-resume-pipeline");
  await resumeButton.waitFor({ state: "visible" });

  const availableDetail = await page.locator("#run-recovery-detail").textContent();
  if (!availableDetail || !availableDetail.includes("recorded answer")) {
    throw new Error(`Missing explicit availability detail on run detail: ${availableDetail}`);
  }

  const availableEffect = await page.locator("#run-recovery-effect").textContent();
  if (!availableEffect || !availableEffect.includes("same run id")) {
    throw new Error(`Missing qualified continuity framing before resume: ${availableEffect}`);
  }

  await resumeButton.click();

  await page.locator("#run-recovery-receipt-label").waitFor({ state: "visible" });

  const receiptLabel = await page.locator("#run-recovery-receipt-label").textContent();
  if (!receiptLabel || !receiptLabel.includes("Checkpoint resume started")) {
    throw new Error(`Missing resume receipt label: ${receiptLabel}`);
  }

  const receiptDetail = await page.locator("#run-recovery-receipt-detail").textContent();
  const receiptKnownLimit = await page.locator("#run-recovery-receipt-known-limit").textContent();

  if (!receiptDetail || !receiptDetail.includes("same run id")) {
    throw new Error(`Missing same-run continuity detail on receipt: ${receiptDetail}`);
  }

  if (
    !receiptKnownLimit ||
    !receiptKnownLimit.includes("qualified checkpoint-backed continuity slice on the same run id only")
  ) {
    throw new Error(`Missing qualified continuity known-limit on receipt: ${receiptKnownLimit}`);
  }

  await waitFor(async () => {
    const { body } = await jsonRequest(`/pipelines/${pipelineId}`);
    return body.status === "success" ? body : null;
  }, "pipeline to complete after resume", 300);

  console.log(
    [
      "SABLE_OPERATOR_JOURNEY_OK",
      `pipeline_id=${pipelineId}`,
      "refusal_seen=true",
      "availability_seen=true",
      "qualified_continuity_seen=true"
    ].join(" ")
  );
} finally {
  await browser.close();
}
