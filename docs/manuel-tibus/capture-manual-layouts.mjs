#!/usr/bin/env node
/**
 * Captures écrans « layout » pour les manuels (sidebar, header Tibus Africa, grilles pastels).
 * Ne remplace PAS les résultats de scan ni les reçus.
 *
 * Compte démo : tabiscompany@gmail.com (super admin — tous les rôles)
 *
 * Usage :
 *   MANUAL_CAPTURE_BASE=https://tibus.app node docs/manuel-tibus/capture-manual-layouts.mjs
 *
 * Note : les routes owner/admin enfants exigent une navigation SPA (clic sur les liens).
 * Un rechargement direct (page.goto) peut rediriger vers l'accueil avant hydratation Supabase.
 */

import { chromium } from "playwright";
import { cpSync, existsSync, mkdirSync, readdirSync } from "fs";
import { join, dirname } from "path";
import { fileURLToPath } from "url";

const __dir = dirname(fileURLToPath(import.meta.url));

const OUT = join(__dir, "../../public/manuel/captures");
const DOCS_OUT = join(__dir, "captures");
const BASE = process.env.MANUAL_CAPTURE_BASE ?? "https://tibus.app";
const EMAIL = process.env.MANUAL_CAPTURE_EMAIL ?? "tabiscompany@gmail.com";
const PASSWORD = process.env.MANUAL_CAPTURE_PASSWORD ?? "123456";
const LOCALE = process.env.MANUAL_CAPTURE_LOCALE ?? "fr";
const COMPANY_HINT = process.env.MANUAL_CAPTURE_COMPANY ?? "Démo";

/** Fichiers à ne jamais écraser (résultats scan, reçus, etc.) */
const SKIP_FILES = new Set([
  "scan-controle-orange-doublon.png",
  "scan-controle-orange.png",
  "scan-controle-rouge-fraude.png",
  "scan-controle-rouge.png",
  "scan-controle-vert-onboard.png",
  "scan-controle-vert-valid.png",
  "scan-controle-vert.png",
  "seller-scan-already-onboard.png",
  "seller-scan-duplicate.png",
  "seller-scan-onboard-confirmed.png",
  "seller-scan-valid.png",
  "owner-real-company-test.png",
]);

/** [filename, path relatif /{locale}/…] — owner en premier (session SPA) */
const LAYOUT_ROUTES = [
  ["owner-real-overview.png", `/${LOCALE}/owner`],
  ["owner-real-sales.png", `/${LOCALE}/owner/sales`],
  ["owner-real-guarantee-fund.png", `/${LOCALE}/owner/guarantee-fund`],
  ["owner-real-cash-register.png", `/${LOCALE}/owner/cash-register`],
  ["owner-real-gare-manager-commissions.png", `/${LOCALE}/owner/gare-manager-commissions`],
  ["owner-real-expenses.png", `/${LOCALE}/owner/expenses`],
  ["owner-real-income-statement.png", `/${LOCALE}/owner/income-statement`],
  ["owner-real-partner-api.png", `/${LOCALE}/owner/partner-api`],
  ["owner-real-company.png", `/${LOCALE}/owner/company`],
  ["owner-real-reviews.png", `/${LOCALE}/owner/reviews`],
  ["owner-real-promo-codes.png", `/${LOCALE}/owner/promo-codes`],
  ["owner-real-subscription.png", `/${LOCALE}/owner/subscription`],
  ["owner-real-analytics.png", `/${LOCALE}/owner/analytics`],
  ["owner-real-analytics-tickets.png", `/${LOCALE}/owner/analytics/tickets`],
  ["owner-real-analytics-trips.png", `/${LOCALE}/owner/analytics/trips`],
  ["owner-real-analytics-travelers.png", `/${LOCALE}/owner/analytics/travelers`],
  ["owner-real-messages.png", `/${LOCALE}/owner/messages`],
  ["owner-real-loyalty.png", `/${LOCALE}/owner/loyalty`],
  ["owner-real-colis.png", `/${LOCALE}/owner/colis`],
  ["owner-real-cancellation-policy.png", `/${LOCALE}/owner/cancellation`],
  ["owner-real-buses.png", `/${LOCALE}/owner/buses`],
  ["owner-real-stations.png", `/${LOCALE}/owner/stations`],
  ["owner-real-routes.png", `/${LOCALE}/owner/routes`],
  ["owner-real-trips.png", `/${LOCALE}/owner/trips`],
  ["owner-real-sellers.png", `/${LOCALE}/owner/sellers`],
  ["owner-real-scan.png", `/${LOCALE}/verify/scan`],
  ["seller-real-dashboard.png", `/${LOCALE}/seller`],
  ["admin-real-panel.png", `/${LOCALE}/admin`],
  ["admin-real-demarcheur.png", `/${LOCALE}/admin/demarcheur`],
  ["admin-real-guarantee-fund.png", `/${LOCALE}/admin/guarantee-fund`],
  ["capture-accueil.png", `/${LOCALE}`],
  ["capture-guide.png", `/${LOCALE}/guide`],
  ["capture-recherche.png", `/${LOCALE}/traveler/search`],
];

const OWNER_PREFIX = `/${LOCALE}/owner`;
const ADMIN_PREFIX = `/${LOCALE}/admin`;
const HARD_GOTO_OK = new Set([
  `/${LOCALE}`,
  `/${LOCALE}/guide`,
  `/${LOCALE}/traveler/search`,
  `/${LOCALE}/seller`,
  `/${LOCALE}/admin`,
]);

mkdirSync(OUT, { recursive: true });

function pathSuffix(path) {
  return path.replace(`/${LOCALE}`, "") || "/";
}

function isOwnerArea(path) {
  return path.startsWith(OWNER_PREFIX) || path === `/${LOCALE}/verify/scan`;
}

function isAdminSubRoute(path) {
  return path.startsWith(`${ADMIN_PREFIX}/`);
}

async function login(page) {
  console.log(`Login ${EMAIL} on ${BASE}...`);
  await page.goto(`${BASE}/${LOCALE}/auth/login`, { waitUntil: "domcontentloaded", timeout: 60000 });
  await page.waitForTimeout(1000);

  await page.locator("input#signin-email").fill(EMAIL);
  await page.locator("input#signin-password").fill(PASSWORD);

  const cguCheckbox = page.locator("#signin-cgu");
  if (await cguCheckbox.isVisible()) {
    await cguCheckbox.check();
  }

  const submitBtn = page.getByRole("button", { name: /se connecter|sign in|connexion/i });
  await submitBtn.click();
  await page.waitForURL((url) => !url.pathname.includes("/auth/login"), { timeout: 60000 });
  await page.waitForTimeout(3000);
}

async function dismissOverlays(page) {
  const closeButtons = page.getByRole("button", { name: /fermer|close|plus tard|skip|ignorer/i });
  if (await closeButtons.count()) {
    try {
      await closeButtons.first().click({ timeout: 2000 });
    } catch {
      /* optional tour dialog */
    }
  }
}

async function selectDemoCompany(page) {
  const trigger = page.locator('[role="combobox"]').first();
  if (!(await trigger.isVisible().catch(() => false))) return;

  await trigger.click();
  const option = page.getByRole("option", { name: new RegExp(COMPANY_HINT, "i") }).first();
  if (await option.count()) {
    await option.click();
    await page.waitForTimeout(1500);
    console.log(`  Compagnie sélectionnée (${COMPANY_HINT})`);
  } else {
    await page.keyboard.press("Escape");
  }
}

async function clickVisibleLink(page, href) {
  const clicked = await page.evaluate((targetHref) => {
    const links = [...document.querySelectorAll(`a[href="${targetHref}"]`)];
    const link = links.find((el) => {
      const rect = el.getBoundingClientRect();
      return rect.width > 0 && rect.height > 0;
    });
    if (!link) return false;
    link.click();
    return true;
  }, href);
  if (!clicked) {
    throw new Error(`Aucun lien visible pour ${href}`);
  }
}

async function openOwnerFromHome(page) {
  const href = `/${LOCALE}/owner`;
  if (!page.url().endsWith(`/${LOCALE}`) && !page.url().endsWith(`/${LOCALE}/`)) {
    await page.goto(`${BASE}/${LOCALE}`, { waitUntil: "load", timeout: 60000 });
    await page.waitForTimeout(2000);
  }
  await clickVisibleLink(page, href);
  await page.waitForURL(`**/${LOCALE}/owner**`, { timeout: 30000 });
  await page.waitForTimeout(2000);
}

async function ensureOwnerShell(page) {
  const onOwner =
    page.url().includes(`/${LOCALE}/owner`) || page.url().includes(`/${LOCALE}/verify/scan`);
  if (!onOwner) {
    await openOwnerFromHome(page);
  }
  await page.getByRole("navigation").first().waitFor({ state: "visible", timeout: 30000 });
  await selectDemoCompany(page);
}

async function ensureAdminShell(page) {
  if (!page.url().includes(`/${LOCALE}/admin`)) {
    await page.goto(`${BASE}/${LOCALE}/admin`, { waitUntil: "load", timeout: 60000 });
    await page.waitForTimeout(3000);
  }
}

async function navigateViaHistory(page, href) {
  await page.evaluate((path) => {
    window.history.pushState({}, "", path);
    window.dispatchEvent(new PopStateEvent("popstate"));
  }, href);
  await page.waitForURL(`**${href}**`, { timeout: 30000 });
  await page.waitForTimeout(2000);
}

async function clickAppLink(page, href) {
  const navLink = page.locator(`nav a[href="${href}"]`).first();
  if (await navLink.count()) {
    await navLink.click();
    return;
  }

  const anyLink = page.locator(`a[href="${href}"]`).first();
  if (await anyLink.count()) {
    await anyLink.click();
    return;
  }

  if (href.startsWith(OWNER_PREFIX)) {
    const onOverview = page.url().includes(`/${LOCALE}/owner`) && !page.url().includes("/owner/");
    if (!onOverview) {
      await clickVisibleLink(page, OWNER_PREFIX);
      await page.waitForURL(`**${OWNER_PREFIX}**`, { timeout: 30000 });
      await page.waitForTimeout(1500);
    }
    const gridLink = page.locator(`main a[href="${href}"], [data-tour] a[href="${href}"]`).first();
    if (await gridLink.count()) {
      await gridLink.click();
      return;
    }
  }

  if (page.url().includes(`/${LOCALE}/owner`) || page.url().includes(`/${LOCALE}/admin`)) {
    await navigateViaHistory(page, href);
    return;
  }

  throw new Error(`Lien introuvable : ${href}`);
}

async function navigateTo(page, path) {
  const target = path.startsWith(`/${LOCALE}`) ? path : `/${LOCALE}${path}`;
  const current = new URL(page.url()).pathname.replace(/\/$/, "") || `/${LOCALE}`;
  const normalizedTarget = target.replace(/\/$/, "") || `/${LOCALE}`;

  if (current === normalizedTarget) {
    await page.waitForTimeout(1000);
    return;
  }

  if (HARD_GOTO_OK.has(normalizedTarget)) {
    await page.goto(`${BASE}${normalizedTarget}`, { waitUntil: "load", timeout: 60000 });
    await page.waitForTimeout(2500);
    return;
  }

  if (isOwnerArea(normalizedTarget)) {
    await ensureOwnerShell(page);

    if (normalizedTarget === OWNER_PREFIX) {
      await page.waitForTimeout(1000);
      return;
    }

    if (normalizedTarget.includes("/owner/analytics/")) {
      const analyticsPath = `/${LOCALE}/owner/analytics`;
      if (!page.url().includes(analyticsPath)) {
        await clickAppLink(page, analyticsPath);
        await page.waitForURL(`**${analyticsPath}**`, { timeout: 30000 });
        await page.waitForTimeout(1500);
      }
    }

    await clickAppLink(page, normalizedTarget);
    await page.waitForURL(`**${normalizedTarget}**`, { timeout: 30000 });
    await page.waitForTimeout(2500);
    return;
  }

  if (isAdminSubRoute(normalizedTarget)) {
    await ensureAdminShell(page);
    try {
      await clickAppLink(page, normalizedTarget);
    } catch {
      await page.goto(`${BASE}/${LOCALE}`, { waitUntil: "load", timeout: 60000 });
      await page.waitForTimeout(1500);
      await clickVisibleLink(page, normalizedTarget);
    }
    await page.waitForURL(`**${normalizedTarget}**`, { timeout: 30000 });
    await page.waitForTimeout(2500);
    return;
  }

  await page.goto(`${BASE}${normalizedTarget}`, { waitUntil: "load", timeout: 60000 });
  await page.waitForTimeout(2500);
}

function syncToDocsCaptures() {
  mkdirSync(DOCS_OUT, { recursive: true });
  for (const file of readdirSync(OUT)) {
    if (!file.endsWith(".png") || SKIP_FILES.has(file)) continue;
    cpSync(join(OUT, file), join(DOCS_OUT, file));
  }
  console.log("Sync →", DOCS_OUT);
}

const browser = await chromium.launch({
  headless: true,
  channel: process.env.PLAYWRIGHT_CHANNEL ?? "chrome",
});
const context = await browser.newContext({
  viewport: { width: 1440, height: 900 },
  deviceScaleFactor: 2,
});
const page = await context.newPage();

const failures = [];

try {
  await login(page);
  await dismissOverlays(page);

  for (const [filename, path] of LAYOUT_ROUTES) {
    if (SKIP_FILES.has(filename)) {
      console.log(`Skip (protected): ${filename}`);
      continue;
    }
    console.log(`Capture ${filename} ← ${path}`);
    try {
      await navigateTo(page, path);
      await dismissOverlays(page);

      const landed = new URL(page.url()).pathname.replace(/\/$/, "");
      const expected = path.replace(/\/$/, "");
      if (!landed.endsWith(pathSuffix(path)) && landed !== expected) {
        throw new Error(`URL inattendue : ${landed} (attendu ${expected})`);
      }

      await page.screenshot({
        path: join(OUT, filename),
        fullPage: true,
      });
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      console.error(`  FAILED ${filename}:`, message);
      failures.push({ filename, message });
    }
  }
} finally {
  await browser.close();
}

if (existsSync(OUT)) {
  syncToDocsCaptures();
}

console.log("Done:", OUT);
if (failures.length) {
  console.error(`${failures.length} échec(s) :`, failures.map((f) => f.filename).join(", "));
  process.exitCode = 1;
}
