export const INVESTOR_PLAN_META = {
  title: "Tibus — Plan d'affaires & ROI investisseur",
  date: "Juin 2026",
  product: "SaaS billetterie bus interurbaine · Afrique de l'Ouest",
  url: "https://tibus-front.vercel.app",
  currency: "XOF (FCFA)",
  eurRate: 655.957,
};

export const INVESTOR_PLAN_LEVEE = {
  amountXof: 250_000_000,
  dilution: "18 – 22 %",
  runway: "18 mois de runway",
  usage: [
    { label: "Commercial & onboarding compagnies", share: 35 },
    { label: "Produit & ingénierie (fin migration Supabase)", share: 30 },
    { label: "Ops paiements & conformité", share: 15 },
    { label: "Marketing acquisition voyageurs", share: 12 },
    { label: "Fonds de roulement & imprévus", share: 8 },
  ],
};

export const INVESTOR_PLAN_PROJECTIONS = [
  { year: "An 0 (actuel)", companies: 3, ticketsMonth: 800, avgTicket: 8000, aboMonth: 0, takeRate: 0.05 },
  { year: "An 1", companies: 18, ticketsMonth: 9_500, avgTicket: 8000, aboMonth: 25_000, takeRate: 0.055 },
  { year: "An 2", companies: 52, ticketsMonth: 38_000, avgTicket: 8_500, aboMonth: 30_000, takeRate: 0.06 },
  { year: "An 3", companies: 125, ticketsMonth: 125_000, avgTicket: 9_000, aboMonth: 35_000, takeRate: 0.062 },
] as const;

export type InvestorRoiInputs = {
  companies: number;
  ticketsMonth: number;
  avgTicket: number;
  takeRatePct: number;
  aboMonth: number;
  investmentXof: number | null;
  equityPct: number;
  revenueSharePct: number;
  exitMultiple: number;
  horizonYears: number;
};

export const DEFAULT_INVESTOR_ROI_INPUTS: InvestorRoiInputs = {
  companies: 3,
  ticketsMonth: 800,
  avgTicket: 8000,
  takeRatePct: 5,
  aboMonth: 0,
  investmentXof: 5_000_000,
  equityPct: 20,
  revenueSharePct: 15,
  exitMultiple: 5,
  horizonYears: 3,
};

export type InvestorRevenueShareRow = {
  label: string;
  platformRevenue: number;
  annualPayout: number;
  cumulativePayout: number;
  cumulativeNet: number | null;
  recoveryPct: number | null;
};

export function computeInvestorRevenueSharing(inputs: InvestorRoiInputs) {
  const financials = computeInvestorFinancials().slice(1, 1 + Math.max(1, inputs.horizonYears));
  const investment = inputs.investmentXof;
  let cumulative = 0;

  const years: InvestorRevenueShareRow[] = financials.map((row) => {
    const annualPayout = row.revTotal * (inputs.revenueSharePct / 100);
    cumulative += annualPayout;
    return {
      label: row.year,
      platformRevenue: row.revTotal,
      annualPayout,
      cumulativePayout: cumulative,
      cumulativeNet:
        investment != null ? cumulative - investment : null,
      recoveryPct:
        investment != null && investment > 0 ? (cumulative / investment) * 100 : null,
    };
  });

  const lastYear = financials[financials.length - 1];
  const exitStake =
    lastYear != null
      ? lastYear.revTotal * inputs.exitMultiple * (inputs.equityPct / 100)
      : 0;
  const totalRevenueShare = cumulative;
  const totalReturn = totalRevenueShare + exitStake;
  const totalRoi =
    investment != null && investment > 0 ? totalReturn / investment : null;
  const revenueShareOnlyRoi =
    investment != null && investment > 0 ? totalRevenueShare / investment : null;

  return {
    years,
    exitStake,
    totalRevenueShare,
    totalReturn,
    totalRoi,
    revenueShareOnlyRoi,
    investment,
    revenueSharePct: inputs.revenueSharePct,
    equityPct: inputs.equityPct,
    exitMultiple: inputs.exitMultiple,
  };
}

export function fmtInvestorXof(value: number | null, suffix = " XOF") {
  if (value == null) return "—";
  const abs = Math.abs(value);
  if (abs >= 1_000_000_000) return `${(value / 1_000_000_000).toFixed(2)} Md${suffix}`;
  if (abs >= 1_000_000) return `${(value / 1_000_000).toFixed(2)} M${suffix}`;
  if (abs >= 1_000) return `${(value / 1_000).toFixed(1)} k${suffix}`;
  return `${Math.round(value).toLocaleString("fr-FR")}${suffix}`;
}

export function fmtInvestorMultiple(value: number | null) {
  if (value == null) return "—";
  return `×${value.toFixed(2)}`;
}

export function fmtInvestorPercent(value: number | null) {
  if (value == null) return "—";
  return `${(value * 100).toFixed(1)} %`;
}

export function computeInvestorFinancials() {
  return INVESTOR_PLAN_PROJECTIONS.map((row) => {
    const gmvYear = row.ticketsMonth * 12 * row.avgTicket;
    const revCommission = gmvYear * row.takeRate;
    const revAbo = row.companies * row.aboMonth * 12;
    const revTotal = revCommission + revAbo;
    const ebitdaMargin =
      row.year === "An 0 (actuel)" ? -0.9 : row.year === "An 1" ? -0.35 : row.year === "An 2" ? 0.08 : 0.22;
    return {
      ...row,
      gmvYear,
      revCommission,
      revAbo,
      revTotal,
      ebitda: revTotal * ebitdaMargin,
    };
  });
}

export function computeInvestorRoi(inputs: InvestorRoiInputs) {
  const takeRate = inputs.takeRatePct / 100;
  const equity = inputs.equityPct / 100;
  const gmvYear = inputs.ticketsMonth * 12 * inputs.avgTicket;
  const revCommission = gmvYear * takeRate;
  const revAbo = inputs.companies * inputs.aboMonth * 12;
  const revTotal = revCommission + revAbo;
  const exitValuation = revTotal * inputs.exitMultiple;
  const stakeValue = exitValuation * equity;
  const roi =
    inputs.investmentXof != null && inputs.investmentXof > 0
      ? stakeValue / inputs.investmentXof
      : null;
  const irr =
    roi != null && inputs.horizonYears > 0
      ? Math.pow(roi, 1 / inputs.horizonYears) - 1
      : null;
  const gain =
    roi != null && inputs.investmentXof != null && inputs.investmentXof > 0
      ? stakeValue - inputs.investmentXof
      : null;

  return {
    gmvYear,
    revCommission,
    revAbo,
    revTotal,
    exitValuation,
    stakeValue,
    roi,
    irr,
    gain,
  };
}

export const INVESTOR_PLAN_MARKET = {
  headers: ["Segment", "Description", "Taille indicative", "Horizon"],
  rows: [
    ["TAM", "Transport interurbain Afrique de l'Ouest + CEAC", "~12 Md USD / an de billetterie", "5–7 ans"],
    ["SAM", "Compagnies structurées UEMOA + CI + CM + GA", "~1,2 Md USD", "3–5 ans"],
    ["SOM (An 3)", "120 compagnies actives sur Tibus", "~92 Md XOF GMV / an", "36 mois"],
    ["Ticket moyen", "Ligne interurbaine régionale", "8 000 XOF", "Hypothèse base"],
    ["Take rate net", "Commission plateforme après frais MM", "4,5 – 6,5 % du GMV", "Configurable par pays"],
  ],
};

export const INVESTOR_PLAN_REVENUE_MODEL = {
  headers: ["Flux de revenu", "Mécanisme", "Part revenu An 3 (base)"],
  rows: [
    ["Commission billet (X%)", "M×X% sur chaque billet payé — configurable pays/compagnie", "78 %"],
    ["Abonnements B2B", "Plans SaaS compagnie (durées 1 mois → 1 an)", "14 %"],
    ["Colis & services", "Colis liés au billet + module autonome", "5 %"],
    ["Réseau vendeurs", "Répartition stakeholder sur pool commission (non marge brute Tibus)", "—"],
  ],
};

export const INVESTOR_PLAN_ROADMAP = {
  headers: ["Phase", "Période", "Objectifs", "KPI clé"],
  rows: [
    ["Pilote → PMF", "M0 – M6", "10 compagnies payantes CI/TG/BJ · paiement FedaPay stable", "500+ billets / jour"],
    ["Expansion UEMOA", "M7 – M12", "52 compagnies · vendeurs réseau · colis", "3 000+ billets / jour"],
    ["Scale régional", "M13 – M24", "CM/GA/SN · TPE Android · abonnements récurrents", "8 000+ billets / jour"],
    ["Leadership", "M25 – M36", "125+ compagnies · API partenaires · data analytics", "125 k+ billets / mois"],
  ],
};

export const INVESTOR_PLAN_ADVANTAGES = {
  headers: ["Avantage", "Preuve / différenciation"],
  rows: [
    ["Stack production-ready", "App live Vercel + Supabase · multi-rôles · QR · mobile money"],
    ["Monétisation flexible", "Commission X% par pays/compagnie · payeur compagnie ou voyageur"],
    ["Réseau commercial intégré", "Vendeurs indépendants, masters, guichet cash, TPE"],
    ["Barrières opérationnelles", "Fond de garantie · RLS multi-tenant · audit admin"],
    ["Coût infra maîtrisé", "Démarrage < 35 €/mois · scaling documenté jusqu'à national"],
  ],
};

export const INVESTOR_PLAN_RISKS = {
  headers: ["Risque", "Impact", "Mitigation"],
  rows: [
    ["Adoption compagnies (change management)", "Élevé", "Onboarding Owner + manuel 22 modules · démo Tibus"],
    ["Dépendance opérateurs MM", "Moyen", "Multi-gateway (FedaPay, GeniusPay) · hints réseau par pays"],
    ["Concurrence locale / guichet", "Moyen", "Omnicanal guichet + web · fidélité · colis"],
    ["Migration technique", "Moyen", "Supabase 80 %+ migré · cutover planifié"],
    ["Réglementation / KYC", "Moyen", "Partenariat PSP agréé · séparation fonds garantie"],
  ],
};

export function buildInvestorRoiScenarioRows() {
  const financials = computeInvestorFinancials();
  const base = financials[3];
  const levee = INVESTOR_PLAN_LEVEE.amountXof;

  return {
    headers: [
      "Scénario",
      "Revenu An 3",
      "Multiple sortie",
      "Valorisation",
      "Part 20 %",
      "ROI brut",
      "TRI 3 ans",
    ],
    rows: [
      [
        "Prudent",
        fmtInvestorXof(420_000_000),
        "4×",
        fmtInvestorXof(1_680_000_000),
        fmtInvestorXof(336_000_000),
        "×1,3",
        "~9 %",
      ],
      [
        "Base",
        fmtInvestorXof(base.revTotal),
        "5×",
        fmtInvestorXof(base.revTotal * 5),
        fmtInvestorXof(base.revTotal),
        fmtInvestorMultiple(base.revTotal / levee),
        "~38 %",
      ],
      [
        "Optimiste",
        fmtInvestorXof(950_000_000),
        "7×",
        fmtInvestorXof(6_650_000_000),
        fmtInvestorXof(1_330_000_000),
        "×5,3",
        "~73 %",
      ],
    ],
  };
}
