#!/usr/bin/env node
/** Capture écrans Owner connecté — compte démo tibustest */

import { chromium } from "playwright";
import { mkdirSync } from "fs";
import { join, dirname } from "path";
import { fileURLToPath } from "url";

const __dir = dirname(fileURLToPath(import.meta.url));
const OUT = join(__dir, "../../public/manuel/captures");
const BASE = process.env.MANUAL_CAPTURE_BASE ?? "https://tibus.app";
const EMAIL = process.env.MANUAL_CAPTURE_EMAIL ?? "tibustest@gmail.com";
const PASSWORD = process.env.MANUAL_CAPTURE_PASSWORD ?? "123456";

const ROUTES = [
  ["overview", "/fr/owner"],
  ["guarantee-fund", "/fr/owner/guarantee-fund"],
  ["gare-manager-commissions", "/fr/owner/gare-manager-commissions"],
  ["expenses", "/fr/owner/expenses"],
  ["income-statement", "/fr/owner/income-statement"],
  ["partner-api", "/fr/owner/partner-api"],
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

console.log(`Login ${EMAIL} on ${BASE}...`);
await page.goto(`${BASE}/fr/auth/login`, { waitUntil: "networkidle" });
await page.getByLabel(/email/i).fill(EMAIL);
await page.getByLabel(/mot de passe|password/i).fill(PASSWORD);
await page.getByRole("button", { name: /se connecter|sign in/i }).click();
await page.waitForURL(/\/fr(\/owner)?/, { timeout: 45000 });

for (const [slug, path] of ROUTES) {
  console.log(`Capture ${slug}...`);
  await page.goto(`${BASE}${path}`, { waitUntil: "networkidle" });
  await page.waitForTimeout(2000);
  await page.screenshot({
    path: join(OUT, `owner-real-${slug}.png`),
    fullPage: true,
  });
}

await browser.close();
console.log("Done:", OUT);
