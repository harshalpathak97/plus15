// Headless "Export bundle" for one deck, the same path as the toolbar button.
//   node scripts/export.mjs [device] [outDir]     (dev server must be running)
// device: android (default) | android-7 | android-10 | feature-graphic
// Uses system Chrome via Playwright, as tests/harness/bug-bash.cjs does.
import { chromium } from "playwright";
import JSZip from "jszip";
import fs from "node:fs/promises";
import path from "node:path";

const device = process.argv[2] || "android";
const out = path.resolve(process.argv[3] || "out");
const base = process.env.EDITOR_URL || "http://localhost:3000";

const project = await (await fetch(`${base}/api/project`)).json();
const state = { ...project.state, device, locale: project.state.locales?.[0] || "en" };
const saved = await fetch(`${base}/api/project`, {
  method: "POST",
  headers: { "content-type": "application/json" },
  body: JSON.stringify(state),
});
if (!saved.ok) throw new Error(`POST /api/project ${saved.status}: ${await saved.text()}`);

const browser = await chromium.launch({ channel: "chrome", headless: true });
const page = await browser.newPage({ viewport: { width: 1600, height: 1000 }, acceptDownloads: true });
// The editor paints from localStorage first; clear it so the file wins.
await page.addInitScript(() => localStorage.clear());
await page.goto(base);
const button = page.getByRole("button", { name: "Export bundle", exact: true });
await button.waitFor({ timeout: 120_000 });
await page.waitForTimeout(2500);
const download = page.waitForEvent("download", { timeout: 300_000 });
await button.click();
// Surface editor toasts (e.g. "Images could not be loaded") instead of a bare timeout.
const failed = page.locator("[data-sonner-toast][data-type=error]").first();
const result = await Promise.race([
  download.then((d) => ({ d })),
  failed.waitFor({ timeout: 300_000 }).then(async () => ({ error: await failed.innerText() })),
]);
if (result.error) {
  await browser.close();
  throw new Error(`Export failed: ${result.error}`);
}
const zip = await JSZip.loadAsync(await fs.readFile(await result.d.path()));
await browser.close();

const files = [];
for (const [name, entry] of Object.entries(zip.files)) {
  if (entry.dir || !name.endsWith(".png")) continue;
  const dest = path.join(out, name);
  await fs.mkdir(path.dirname(dest), { recursive: true });
  await fs.writeFile(dest, await entry.async("nodebuffer"));
  files.push(dest);
}
console.log(files.sort().join("\n"));
