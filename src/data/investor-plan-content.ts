export const INVESTOR_PLAN_META = {
  title: "Tibus — Plan d'affaires & ROI investisseur",
  date: "Juin 2026",
  product: "SaaS billetterie bus interurbaine · Afrique de l'Ouest",
  url: "https://tibus-front.vercel.app",
  currency: "XOF (FCFA)",
  eurRate: 655.957,
};

/** Actionnariat — synthèse décisionnelle investisseur. */
export const INVESTOR_CAPITAL = {
  totalXof: 15_000_000,
  investorCashXof: 6_000_000,
  ownerValuationXof: 9_000_000,
  investorEquityPct: 40,
  ownerEquityPct: 60,
  shareFaceValueXof: 1_000,
  investorShares: 6_000,
  ownerShares: 9_000,
  financingNote: "3 000 000 (CAPEX) + 3 000 000 (3 mois OPEX) = 6 000 000 FCFA apport cash investisseur",
};

export const INVESTOR_PLAN_LEVEE = {
  amountXof: INVESTOR_CAPITAL.investorCashXof,
  totalCapitalXof: INVESTOR_CAPITAL.totalXof,
  dilution: `${INVESTOR_CAPITAL.investorEquityPct} %`,
  runway: "Phase startup · CAPEX + 3 mois OPEX",
  usage: [
    { label: "CAPEX (développement & mise en production)", share: 50 },
    { label: "OPEX — 3 premiers mois", share: 50 },
  ],
};

export type InvestorScenarioId = "pessimistic" | "realistic" | "optimistic";

export type InvestorScenarioDefinition = {
  id: InvestorScenarioId;
  label: string;
  description: string;
  ticketsMonth: readonly number[];
  opexYear: readonly number[];
  investorNotes: readonly string[];
  referenceCumulativeNet5y: number;
};

/** Scénarios A / B / C — pilotés par le volume de billets (pas le nombre de compagnies). */
export const INVESTOR_SCENARIOS: Record<InvestorScenarioId, InvestorScenarioDefinition> = {
  pessimistic: {
    id: "pessimistic",
    label: "Scénario A — Pessimiste",
    description:
      "Adoption lente · croissance ~40 % · résistance réseau traditionnel · déploiement agents difficile",
    ticketsMonth: [5_000, 10_000, 20_000, 35_000, 50_000],
    opexYear: [24_000_000, 24_000_000, 24_000_000, 24_000_000, 24_000_000],
    investorNotes: [
      "Déficit An 1",
      "Point mort",
      "Remboursement An 3",
      "Profit net solide",
      "Cumulé 5 ans : 168 M",
    ],
    referenceCumulativeNet5y: 168_000_000,
  },
  realistic: {
    id: "realistic",
    label: "Scénario B — Réaliste",
    description:
      "Objectif de base · déploiement fluide · montée en charge progressive · réseau agents marchands",
    ticketsMonth: [10_000, 25_000, 50_000, 80_000, 120_000],
    opexYear: [24_000_000, 24_000_000, 26_000_000, 28_000_000, 30_000_000],
    investorNotes: [
      "Équilibre An 1",
      "Remboursement mi-An 2",
      "Forte rentabilité",
      "Expansion",
      "Cumulé 5 ans : 552 M",
    ],
    referenceCumulativeNet5y: 552_000_000,
  },
  optimistic: {
    id: "optimistic",
    label: "Scénario C — Optimiste",
    description:
      "Adoption rapide · contrats d'exclusivité · effet réseau massif · 2 leaders signent dès le départ",
    ticketsMonth: [18_000, 45_000, 85_000, 130_000, 200_000],
    opexYear: [24_000_000, 28_000_000, 32_000_000, 36_000_000, 40_000_000],
    investorNotes: [
      "Remboursement fin An 1",
      "Dividendes élevés",
      "Hyper-croissance",
      "Leader régional",
      "Cumulé 5 ans : 987 M",
    ],
    referenceCumulativeNet5y: 987_000_000,
  },
};

export type InvestorRoiInputs = {
  scenarioId: InvestorScenarioId;
  avgTicket: number;
  tibusTakeRatePct: number;
  volumeMultiplierPct: number;
  investmentXof: number | null;
  investorEquityPct: number;
  horizonYears: number;
};

export const DEFAULT_INVESTOR_ROI_INPUTS: InvestorRoiInputs = {
  scenarioId: "realistic",
  avgTicket: 10_000,
  tibusTakeRatePct: 2,
  volumeMultiplierPct: 100,
  investmentXof: INVESTOR_CAPITAL.investorCashXof,
  investorEquityPct: INVESTOR_CAPITAL.investorEquityPct,
  horizonYears: 5,
};

export type InvestorScenarioYearRow = {
  yearLabel: string;
  yearIndex: number;
  ticketsMonth: number;
  annualTickets: number;
  gmv: number;
  tibusRevenue: number;
  opex: number;
  netResult: number;
  investorShare: number;
  ownerShare: number;
  cumulativeNet: number;
  cumulativeInvestorShare: number;
  cumulativeOwnerShare: number;
  investorRecoveryPct: number | null;
  investorNote: string;
};

export type InvestorScenarioProjection = {
  scenario: InvestorScenarioDefinition;
  years: InvestorScenarioYearRow[];
  cumulativeNet: number;
  cumulativeInvestorShare: number;
  cumulativeOwnerShare: number;
  investorRoi: number | null;
};

export function fmtInvestorXof(value: number | null, suffix = " XOF") {
  if (value == null) return "—";
  const abs = Math.abs(value);
  const sign = value < 0 ? "−" : "";
  const formatted =
    abs >= 1_000_000_000
      ? `${(abs / 1_000_000_000).toFixed(2)} Md`
      : abs >= 1_000_000
        ? `${(abs / 1_000_000).toFixed(2)} M`
        : abs >= 1_000
          ? `${(abs / 1_000).toFixed(1)} k`
          : `${Math.round(abs).toLocaleString("fr-FR")}`;
  return `${sign}${formatted}${suffix}`;
}

export function fmtInvestorMultiple(value: number | null) {
  if (value == null) return "—";
  return `×${value.toFixed(2)}`;
}

export function fmtInvestorPercent(value: number | null) {
  if (value == null) return "—";
  return `${(value * 100).toFixed(1)} %`;
}

export function computeInvestorScenarioProjection(
  inputs: InvestorRoiInputs,
): InvestorScenarioProjection {
  const scenario = INVESTOR_SCENARIOS[inputs.scenarioId];
  const ownerPct = 100 - inputs.investorEquityPct;
  const volumeFactor = inputs.volumeMultiplierPct / 100;
  const horizon = Math.min(Math.max(1, inputs.horizonYears), 5);

  let cumulativeNet = 0;
  let cumulativeInvestorShare = 0;
  let cumulativeOwnerShare = 0;

  const years: InvestorScenarioYearRow[] = [];

  for (let index = 0; index < horizon; index += 1) {
    const ticketsMonth = Math.round(scenario.ticketsMonth[index] * volumeFactor);
    const annualTickets = ticketsMonth * 12;
    const gmv = annualTickets * inputs.avgTicket;
    const tibusRevenue = Math.round((gmv * inputs.tibusTakeRatePct) / 100);
    const opex = scenario.opexYear[index];
    const netResult = tibusRevenue - opex;
    // Partage associés : 40 % / 60 % sur 100 % du revenu plateforme (GMV × X %), hors commissions réseau.
    const investorShare = Math.round((tibusRevenue * inputs.investorEquityPct) / 100);
    const ownerShare = Math.round((tibusRevenue * ownerPct) / 100);

    cumulativeNet += netResult;
    cumulativeInvestorShare += investorShare;
    cumulativeOwnerShare += ownerShare;

    const recoveryPct =
      inputs.investmentXof != null && inputs.investmentXof > 0
        ? (cumulativeInvestorShare / inputs.investmentXof) * 100
        : null;

    years.push({
      yearLabel: `An ${index + 1}`,
      yearIndex: index + 1,
      ticketsMonth,
      annualTickets,
      gmv,
      tibusRevenue,
      opex,
      netResult,
      investorShare,
      ownerShare,
      cumulativeNet,
      cumulativeInvestorShare,
      cumulativeOwnerShare,
      investorRecoveryPct: recoveryPct,
      investorNote: scenario.investorNotes[index] ?? "—",
    });
  }

  const investorRoi =
    inputs.investmentXof != null && inputs.investmentXof > 0
      ? cumulativeInvestorShare / inputs.investmentXof
      : null;

  return {
    scenario,
    years,
    cumulativeNet,
    cumulativeInvestorShare,
    cumulativeOwnerShare,
    investorRoi,
  };
}

export function computeAllScenarioSummaries(inputs: Omit<InvestorRoiInputs, "scenarioId">) {
  return (Object.keys(INVESTOR_SCENARIOS) as InvestorScenarioId[]).map((scenarioId) => {
    const projection = computeInvestorScenarioProjection({ ...inputs, scenarioId });
    return {
      scenarioId,
      label: projection.scenario.label,
      cumulativeNet: projection.cumulativeNet,
      cumulativeInvestorShare: projection.cumulativeInvestorShare,
      investorRoi: projection.investorRoi,
      referenceCumulativeNet5y: projection.scenario.referenceCumulativeNet5y,
    };
  });
}

/** @deprecated — conservé pour exports legacy ; utiliser computeInvestorScenarioProjection. */
export function computeInvestorFinancials() {
  const projection = computeInvestorScenarioProjection(DEFAULT_INVESTOR_ROI_INPUTS);
  return projection.years.map((row) => ({
    year: row.yearLabel,
    ticketsMonth: row.ticketsMonth,
    avgTicket: DEFAULT_INVESTOR_ROI_INPUTS.avgTicket,
    gmvYear: row.gmv,
    revTotal: row.tibusRevenue,
    opex: row.opex,
    netResult: row.netResult,
    ebitda: row.netResult,
  }));
}

export function computeInvestorRevenueSharing(inputs: InvestorRoiInputs) {
  const projection = computeInvestorScenarioProjection(inputs);
  const investment = inputs.investmentXof;

  return {
    years: projection.years.map((row) => ({
      label: row.yearLabel,
      platformRevenue: row.tibusRevenue,
      netResult: row.netResult,
      investorShareRate: inputs.investorEquityPct,
      ownerShareRate: 100 - inputs.investorEquityPct,
      annualPayout: row.investorShare,
      ownerPayout: row.ownerShare,
      cumulativePayout: row.cumulativeInvestorShare,
      cumulativeOwnerPayout: row.cumulativeOwnerShare,
      cumulativeNet:
        investment != null ? row.cumulativeInvestorShare - investment : row.cumulativeInvestorShare,
      recoveryPct: row.investorRecoveryPct,
      investorNote: row.investorNote,
    })),
    totalRevenueShare: projection.cumulativeInvestorShare,
    totalOwnerShare: projection.cumulativeOwnerShare,
    totalNet: projection.cumulativeNet,
    totalReturn: projection.cumulativeInvestorShare,
    totalRoi: projection.investorRoi,
    revenueShareOnlyRoi: projection.investorRoi,
    investment,
    investorEquityPct: inputs.investorEquityPct,
    ownerEquityPct: 100 - inputs.investorEquityPct,
    exitStake: null as number | null,
    exitMultiple: null as number | null,
  };
}

export function computeInvestorRoi(inputs: InvestorRoiInputs) {
  const projection = computeInvestorScenarioProjection(inputs);
  const lastYear = projection.years[projection.years.length - 1];
  const investment = inputs.investmentXof;

  return {
    gmvYear: lastYear?.gmv ?? 0,
    revTotal: lastYear?.tibusRevenue ?? 0,
    netYear: lastYear?.netResult ?? 0,
    cumulativeInvestorShare: projection.cumulativeInvestorShare,
    roi: projection.investorRoi,
    irr:
      projection.investorRoi != null && inputs.horizonYears > 0
        ? Math.pow(projection.investorRoi, 1 / inputs.horizonYears) - 1
        : null,
    gain:
      investment != null && projection.investorRoi != null
        ? projection.cumulativeInvestorShare - investment
        : null,
  };
}

export const INVESTOR_CAPITAL_TABLE = {
  headers: ["Actionnaire", "Apport", "Valorisation", "Actions", "Valeur action", "%"],
  rows: [
    [
      "Vous (porteur de projet)",
      "Industrie (Tibus Technology)",
      fmtInvestorXof(INVESTOR_CAPITAL.ownerValuationXof, ""),
      String(INVESTOR_CAPITAL.ownerShares),
      `${INVESTOR_CAPITAL.shareFaceValueXof.toLocaleString("fr-FR")} FCFA`,
      `${INVESTOR_CAPITAL.ownerEquityPct} %`,
    ],
    [
      "Investisseur(s) financier(s)",
      "Cash (startup)",
      fmtInvestorXof(INVESTOR_CAPITAL.investorCashXof, ""),
      String(INVESTOR_CAPITAL.investorShares),
      `${INVESTOR_CAPITAL.shareFaceValueXof.toLocaleString("fr-FR")} FCFA`,
      `${INVESTOR_CAPITAL.investorEquityPct} %`,
    ],
    [
      "CAPITAL TOTAL",
      "—",
      fmtInvestorXof(INVESTOR_CAPITAL.totalXof, ""),
      String(INVESTOR_CAPITAL.investorShares + INVESTOR_CAPITAL.ownerShares),
      `${INVESTOR_CAPITAL.shareFaceValueXof.toLocaleString("fr-FR")} FCFA`,
      "100 %",
    ],
  ],
};

export const INVESTOR_PLAN_MARKET = {
  headers: ["Segment", "Description", "Taille indicative", "Horizon"],
  rows: [
    ["TAM", "Transport interurbain Afrique de l'Ouest + CEAC", "~12 Md USD / an de billetterie", "5–7 ans"],
    ["SAM", "Compagnies structurées UEMOA + CI + CM + GA", "~1,2 Md USD", "3–5 ans"],
    ["Levier opérationnel", "Volume de billets vendus (réseau agents marchands)", "Variable clé", "Mensuel"],
    ["Ticket moyen", "Ligne interurbaine régionale", "10 000 XOF", "Hypothèse base"],
    ["Revenu Tibus", "2 % du volume transactions (GMV)", "200 FCFA / billet", "Modèle document"],
  ],
};

export const INVESTOR_PLAN_REVENUE_MODEL = {
  headers: ["Flux", "Mécanisme", "Hypothèse"],
  rows: [
    ["GMV", "Billets annuels × panier moyen", "Volume = seul levier d'ajustement"],
    [
      "Revenu plateforme (100 %)",
      "GMV × X % (ex. 2 %)",
      "Commission Tibus — hors commissions réseau (vendeurs, masters, agents)",
    ],
    ["OPEX", "Charges fixes (serveurs, support, équipe)", "24 → 40 M selon scénario"],
    ["Résultat net société", "Revenu plateforme − OPEX", "Indicateur de rentabilité (hors partage)"],
    ["Part investisseur(s)", "40 % du revenu plateforme", "Actionnariat 6 M / 15 M capital"],
    ["Part porteur", "60 % du revenu plateforme", "Apport industrie 9 M valorisé"],
    [
      "Commissions réseau",
      "Vendeurs indépendants · masters · agents",
      "Simulé séparément (onglet Commissions stakeholders)",
    ],
  ],
};

export const INVESTOR_PLAN_ROADMAP = {
  headers: ["Phase", "Période", "Objectifs", "KPI clé (billets/mois)"],
  rows: [
    ["Pilote", "M0 – M6", "Réseau agents marchands · 2–3 compagnies pilotes", "5 000 – 10 000"],
    ["Traction", "M7 – M18", "Déploiement fluide · exclusivité ciblée", "25 000 – 50 000"],
    ["Scale", "M19 – M36", "Expansion UEMOA · TPE Android", "80 000 – 120 000"],
    ["Leadership", "M37 – M60", "Contrats exclusivité · effet réseau", "130 000 – 200 000"],
  ],
};

export const INVESTOR_PLAN_ADVANTAGES = {
  headers: ["Avantage", "Preuve / différenciation"],
  rows: [
    ["Levier volume", "Seul paramètre d'ajustement = billets vendus via agents marchands"],
    ["Stack production-ready", "App live Vercel + Supabase · multi-rôles · QR · mobile money"],
    ["Point mort rapide", "Scénario réaliste : équilibre An 1 · remboursement mi-An 2"],
    ["Réseau commercial intégré", "Vendeurs indépendants, masters, guichet cash, TPE"],
    ["Coût infra maîtrisé", "OPEX contrôlé 24–40 M FCFA / an"],
  ],
};

export const INVESTOR_PLAN_RISKS = {
  headers: ["Risque", "Impact", "Mitigation"],
  rows: [
    ["Adoption lente (scénario A)", "Élevé", "40 % volume cible → point mort An 2 · remboursement An 3"],
    ["Déploiement agents", "Élevé", "Réseau marchands · formation · incentives"],
    ["Dépendance opérateurs MM", "Moyen", "Multi-gateway (FedaPay, GeniusPay)"],
    ["Concurrence guichet", "Moyen", "Omnicanal guichet + web"],
    ["Réglementation / KYC", "Moyen", "Partenariat PSP agréé"],
  ],
};

export function buildInvestorRoiScenarioRows() {
  const summaries = computeAllScenarioSummaries(DEFAULT_INVESTOR_ROI_INPUTS);
  return {
    headers: [
      "Scénario",
      "Résultat net cumulé (5 ans)",
      "Part investisseur (40 %)",
      "Référence doc.",
      "ROI investisseur",
    ],
    rows: summaries.map((row) => [
      row.label.replace(" — ", " · "),
      fmtInvestorXof(row.cumulativeNet),
      fmtInvestorXof(row.cumulativeInvestorShare),
      fmtInvestorXof(row.referenceCumulativeNet5y),
      fmtInvestorMultiple(row.investorRoi),
    ]),
  };
}
