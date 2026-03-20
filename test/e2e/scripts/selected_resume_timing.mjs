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
const timings = [];

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

    await jsonRequest(`/pipelines/${pipelineId}/cancel`, {
      method: "POST",
      body: JSON.stringify({})
    });

    await waitFor(async () => {
      const { body } = await jsonRequest(`/pipelines/${pipelineId}`);
      return body.status === "cancelled" ? body : null;
    }, "pipeline to cancel");

    await jsonRequest(`/answer`, {
      method: "POST",
      body: JSON.stringify({ pipeline_id: pipelineId, question_id: "gate", value: "A" })
    });

    await waitFor(async () => {
      const { body } = await jsonRequest(`/pipelines/${pipelineId}`);
      return body.resume_ready === true ? body : null;
    }, "resume readiness");

    const page = await browser.newPage();
    await page.goto(`${baseUrl}/runs/${pipelineId}`, { waitUntil: "networkidle" });

    const resumeButton = page.locator("#run-resume-pipeline");
    await resumeButton.waitFor({ state: "visible" });

    const startTime = performance.now();
    await resumeButton.click();

    await waitFor(async () => {
      const receiptLabel = await page.locator("#run-recovery-receipt-label").textContent().catch(() => "");
      return receiptLabel && receiptLabel.includes("Checkpoint resume started") ? receiptLabel : null;
    }, "run detail to reflect completion", 300);

    const elapsedMs = Math.round(performance.now() - startTime);
    timings.push(elapsedMs);

    if (elapsedMs > 15000) {
      throw new Error(`Resume iteration ${iteration + 1} exceeded the 15s sanity ceiling: ${elapsedMs}ms`);
    }

    await page.close();
  }

  const maxElapsed = Math.max(...timings);

  console.log(
    [
      "RHEA_RESUME_TIMING_OK",
      "iterations=3",
      `max_ms=${maxElapsed}`,
      `samples_ms=${timings.join(",")}`
    ].join(" ")
  );
} finally {
  await browser.close();
}
