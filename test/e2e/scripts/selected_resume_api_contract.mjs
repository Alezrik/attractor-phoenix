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

const pipelineId = `noor_api_resume_${Date.now()}`;
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
  const { response: createResponse, body: createBody } = await jsonRequest("/pipelines", {
    method: "POST",
    body: JSON.stringify({ dot, opts: { pipeline_id: pipelineId } })
  });

  if (createResponse.status !== 202) {
    throw new Error(`Expected pipeline creation to return 202, got ${createResponse.status}`);
  }

  if (createBody.pipeline_id !== pipelineId) {
    throw new Error(`Expected pipeline_id ${pipelineId}, got ${createBody.pipeline_id}`);
  }

  await waitFor(async () => {
    const { body } = await jsonRequest(`/pipelines/${pipelineId}`);
    return body.status === "running" ? body : null;
  }, "pipeline to start");

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

  const { response: answerResponse } = await jsonRequest(
    `/answer`,
    {
      method: "POST",
      body: JSON.stringify({ pipeline_id: pipelineId, question_id: "gate", value: "A" })
    }
  );

  if (answerResponse.status !== 202) {
    throw new Error(`Expected answer to return 202, got ${answerResponse.status}`);
  }

  await waitFor(async () => {
    const { body } = await jsonRequest(`/pipelines/${pipelineId}`);
    return body.resume_ready === true ? body : null;
  }, "resume readiness");

  const page = await browser.newPage();
  await page.goto(`${baseUrl}/runs/${pipelineId}`, { waitUntil: "networkidle" });

  const resumeButton = page.locator("#run-resume-pipeline");
  await resumeButton.waitFor({ state: "visible" });

  const resumeLabel = await page.locator("#run-recovery-label").textContent();
  if (!resumeLabel || !resumeLabel.includes("Checkpoint-backed resume available")) {
    throw new Error(`Missing resume-ready label on run detail: ${resumeLabel}`);
  }

  await resumeButton.click();

  await page.locator("#run-recovery-receipt-label").waitFor({ state: "visible" });

  const receiptLabel = await page.locator("#run-recovery-receipt-label").textContent();
  if (!receiptLabel || !receiptLabel.includes("Checkpoint resume started")) {
    throw new Error(`Missing resume receipt label: ${receiptLabel}`);
  }

  await waitFor(async () => {
    const { body } = await jsonRequest(`/pipelines/${pipelineId}`);
    return body.status === "success" ? body : null;
  }, "pipeline to complete after resume", 300);

  const { response: rejectedResponse, body: rejectedBody } = await jsonRequest(
    `/pipelines/${pipelineId}/resume`,
    { method: "POST", body: JSON.stringify({}) }
  );

  if (rejectedResponse.status !== 409) {
    throw new Error(`Expected a rejected resume after completion, got ${rejectedResponse.status}`);
  }

  if (!String(rejectedBody.error || "").includes("selected cancelled packet")) {
    throw new Error(`Unexpected rejection message: ${JSON.stringify(rejectedBody)}`);
  }

  console.log(
    [
      "NOOR_API_RESUME_CONTRACT_OK",
      `pipeline_id=${pipelineId}`,
      "resume_ready=true",
      "resume_rejected_after_completion=true"
    ].join(" ")
  );
} finally {
  await browser.close();
}
