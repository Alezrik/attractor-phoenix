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
const refusalTimings = [];
const availabilityTimings = [];
const receiptTimings = [];

try {
  for (let iteration = 0; iteration < 3; iteration += 1) {
    const pipelineId = `rhea_resume_${Date.now()}_${iteration}`;

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

    const cancelStart = performance.now();
    await jsonRequest(`/pipelines/${pipelineId}/cancel`, {
      method: "POST",
      body: JSON.stringify({})
    });

    const refusedPayload = await waitFor(async () => {
      const { body } = await jsonRequest(`/pipelines/${pipelineId}`);
      return body.status === "cancelled" && body.recovery?.state === "refused" ? body : null;
    }, "pipeline to cancel");

    const refusalMs = Math.round(performance.now() - cancelStart);
    refusalTimings.push(refusalMs);

    if (!String(refusedPayload.recovery?.refusal_reason || "").includes("human gate is fully cleared")) {
      throw new Error(`Missing explicit refusal reason during timing run: ${JSON.stringify(refusedPayload.recovery)}`);
    }

    const answerStart = performance.now();
    await jsonRequest(`/answer`, {
      method: "POST",
      body: JSON.stringify({ pipeline_id: pipelineId, question_id: "gate", value: "A" })
    });

    const availablePayload = await waitFor(async () => {
      const { body } = await jsonRequest(`/pipelines/${pipelineId}`);
      return body.resume_ready === true && body.recovery?.state === "available" ? body : null;
    }, "resume readiness");

    const availabilityMs = Math.round(performance.now() - answerStart);
    availabilityTimings.push(availabilityMs);

    if (availablePayload.recovery?.refusal_reason !== null) {
      throw new Error(`Expected refusal_reason to clear once available during timing run: ${JSON.stringify(availablePayload.recovery)}`);
    }

    const page = await browser.newPage();
    await page.goto(`${baseUrl}/runs/${pipelineId}`, { waitUntil: "networkidle" });

    const resumeButton = page.locator("#run-resume-pipeline");
    await resumeButton.waitFor({ state: "visible" });

    const resumeStart = performance.now();
    await resumeButton.click();

    await waitFor(async () => {
      const receiptLabel = await page.locator("#run-recovery-receipt-label").textContent().catch(() => "");
      return receiptLabel && receiptLabel.includes("Checkpoint resume started") ? receiptLabel : null;
    }, "run detail to reflect completion", 300);

    const receiptMs = Math.round(performance.now() - resumeStart);
    receiptTimings.push(receiptMs);

    if (refusalMs > 15000 || availabilityMs > 15000 || receiptMs > 15000) {
      throw new Error(
        `Iteration ${iteration + 1} exceeded the 15s sanity ceiling: refusal=${refusalMs}ms availability=${availabilityMs}ms receipt=${receiptMs}ms`
      );
    }

    await page.close();
  }

  const maxRefusal = Math.max(...refusalTimings);
  const maxAvailability = Math.max(...availabilityTimings);
  const maxReceipt = Math.max(...receiptTimings);

  console.log(
    [
      "RHEA_RESUME_TIMING_OK",
      "iterations=3",
      `max_refusal_ms=${maxRefusal}`,
      `max_availability_ms=${maxAvailability}`,
      `max_receipt_ms=${maxReceipt}`,
      `refusal_samples_ms=${refusalTimings.join(",")}`,
      `availability_samples_ms=${availabilityTimings.join(",")}`,
      `receipt_samples_ms=${receiptTimings.join(",")}`
    ].join(" ")
  );
} finally {
  await browser.close();
}
