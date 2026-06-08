#!/usr/bin/env node
/** Capture écrans Owner connecté — tabiscompany@gmail.com */

import { chromium } from "playwright";
import { mkdirSync } from "fs";
import { join, dirname } from "path";
import { fileURLToPath } from "url";

const __dir = dirname(fileURLToPath(import.meta.url));
const OUT = join(__dir, "captures");
const BASE = "http://127.0.0.1:5173";

const ROUTES = [
  ["overview", "/fr/owner"],
  ["company", "/fr/owner/company"],
  ["reviews", "/fr/owner/reviews"],
  ["promo-codes", "/fr/owner/promo-codes"],
  ["subscription", "/fr/owner/subscription"],
  ["analytics", "/fr/owner/analytics"],
  ["analytics-tickets", "/fr/owner/analytics/tickets"],
  ["analytics-trips", "/fr/owner/analytics/trips"],
  ["analytics-travelers", "/fr/owner/analytics/travelers"],
  ["sales", "/fr/owner/sales"],
  ["cash-register", "/fr/owner/cash-register"],
  ["messages", "/fr/owner/messages"],
  ["loyalty", "/fr/owner/loyalty"],
  ["colis", "/fr/owner/colis"],
  ["guarantee-fund", "/fr/owner/guarantee-fund"],
  ["cancellation-policy", "/fr/owner/cancellation-policy"],
  ["buses", "/fr/owner/buses"],
  ["stations", "/fr/owner/stations"],
  ["routes", "/fr/owner/routes"],
  ["trips", "/fr/owner/trips"],
  ["sellers", "/fr/owner/sellers"],
];

mkdirSync(OUT, { recursive: true });

const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 1360, height: 900 } });

await page.goto(`${BASE}/fr/auth/login`, { waitUntil: "networkidle" });
await page.getByLabel("Email").fill("tabiscompany@gmail.com");
await page.getByLabel("Mot de passe").fill("123456");
await page.getByRole("button", { name: "Se connecter" }).click();
await page.waitForURL(/\/fr(\/)?$/, { timeout: 30000 });

for (const [slug, path] of ROUTES) {
  console.log(`Capture ${slug}...`);
  await page.goto(`${BASE}${path}`, { waitUntil: "networkidle" });
  await page.waitForTimeout(1500);
  await page.screenshot({
    path: join(OUT, `owner-real-${slug}.png`),
    fullPage: true,
  });
}

await browser.close();
console.log("Done:", OUT);
