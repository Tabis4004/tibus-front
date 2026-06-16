import type { CompanyFeatureModuleId } from "@/lib/company-feature-modules.ts";

/** Mapping console owner / navigation → module commercial. */
export const OWNER_CONSOLE_MODULE_FEATURE: Record<string, CompanyFeatureModuleId> = {
  sales: "A",
  seller: "A",
  fleet: "A",
  stations: "A",
  routes: "A",
  team: "A",
  trips: "A",
  cash: "A",
  company: "A",
  messages: "A",
  scan: "B",
  cancellation: "B",
  expenses: "C",
  "income-statement": "C",
  analytics: "C",
  "gare-manager-commissions": "C",
  guarantee: "A",
  colis: "D",
  promo: "E",
  loyalty: "E",
  "partner-api": "E",
};

export const OWNER_NAV_SUFFIX_FEATURE: Record<string, CompanyFeatureModuleId> = {
  "/owner/sales": "A",
  "/seller": "A",
  "/owner/buses": "A",
  "/owner/stations": "A",
  "/owner/routes": "A",
  "/owner/sellers": "A",
  "/owner/trips": "A",
  "/owner/cash-register": "A",
  "/owner/company": "A",
  "/owner/messages": "A",
  "/verify/scan": "B",
  "/owner/cancellation": "B",
  "/owner/expenses": "C",
  "/owner/income-statement": "C",
  "/owner/analytics": "C",
  "/owner/gare-manager-commissions": "C",
  "/owner/guarantee-fund": "A",
  "/owner/colis": "D",
  "/owner/promo-codes": "E",
  "/owner/loyalty": "E",
  "/owner/partner-api": "E",
};

export const COMMERCIAL_MODULE_LABELS: Record<
  CompanyFeatureModuleId,
  { title: string; desc: string }
> = {
  A: {
    title: "A — Billetterie & exploitation",
    desc: "Guichet, caisse, flotte, lignes, voyages, équipe, journal des ventes.",
  },
  B: {
    title: "B — Scanner & anti-fraude",
    desc: "Contrôle embarquement QR, annulations.",
  },
  C: {
    title: "C — Comptabilité analytique",
    desc: "Dépenses, compte de résultat, rapports et commissions gares.",
  },
  D: {
    title: "D — Courrier / colis",
    desc: "Colis autonomes sans voyageur.",
  },
  E: {
    title: "E — Performance & options avancées",
    desc: "Codes promo, fidélité, API partenaire.",
  },
  F: {
    title: "F — Équipement TPE",
    desc: "Terminal de paiement (sur devis).",
  },
};
