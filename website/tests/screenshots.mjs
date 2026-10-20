// npx playwright install chromium && SITE_URL=http://127.0.0.1:8770/website/ node website/tests/screenshots.mjs
import { chromium } from 'playwright';
import { mkdirSync } from 'node:fs';

const url = process.env.SITE_URL || 'http://127.0.0.1:8770/website/';
const out = process.env.SHOT_DIR || '/opt/cursor/artifacts/website-hero';
const prefix = process.env.SHOT_PREFIX || 'after';
mkdirSync(out, { recursive: true });

const views = [
  { name: '375', width: 375, height: 812 },
  { name: '390', width: 390, height: 844 },
  { name: '430', width: 430, height: 932 },
  { name: '1440', width: 1440, height: 900 },
];

const browser = await chromium.launch();
for (const view of views) {
  const page = await browser.newPage({
    viewport: { width: view.width, height: view.height },
    deviceScaleFactor: view.width < 700 ? 2 : 1,
  });
  await page.goto(url, { waitUntil: 'domcontentloaded' });
  await page.waitForTimeout(2500);
  try {
    await page.frameLocator('.opening-glass-scene').locator('body[data-ready="1"]').waitFor({ timeout: 12000 });
  } catch {}
  await page.waitForTimeout(800);
  await page.screenshot({ path: `${out}/${prefix}-${view.name}.png`, fullPage: false });
  await page.close();
}
await browser.close();
console.log(`wrote ${views.length} ${prefix} shots to ${out}`);
