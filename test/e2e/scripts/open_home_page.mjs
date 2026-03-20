import { chromium } from "../../../assets/node_modules/playwright/index.mjs";

const url = process.argv[2];

if (!url) {
  console.error("Missing home page URL argument.");
  process.exit(1);
}

const browser = await chromium.launch();

try {
  const page = await browser.newPage();
  await page.goto(url, { waitUntil: "networkidle" });

  const currentUrl = page.url();

  if (currentUrl !== url) {
    console.error(`Expected ${url} but opened ${currentUrl}`);
    process.exit(1);
  }

  console.log(`Opened ${currentUrl}`);
} finally {
  await browser.close();
}
