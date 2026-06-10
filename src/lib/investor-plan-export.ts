import { format } from "date-fns";
import jsPDF from "jspdf";
import autoTable from "jspdf-autotable";
import {
  buildInvestorRoiScenarioRows,
  computeInvestorRevenueSharing,
  computeInvestorRoi,
  computeInvestorScenarioProjection,
  fmtInvestorMultiple,
  fmtInvestorPercent,
  fmtInvestorXof,
  INVESTOR_CAPITAL,
  INVESTOR_CAPITAL_TABLE,
  INVESTOR_PLAN_LEVEE,
  INVESTOR_PLAN_META,
  INVESTOR_SCENARIOS,
  type InvestorRoiInputs,
} from "@/data/investor-plan-content.ts";

function addSectionTitle(doc: jsPDF, title: string, y: number) {
  doc.setFont("helvetica", "bold");
  doc.setFontSize(12);
  doc.text(title, 14, y);
  doc.setFont("helvetica", "normal");
  return y + 6;
}

export function downloadInvestorPlanPdf(roiInputs: InvestorRoiInputs) {
  const doc = new jsPDF({ orientation: "portrait", unit: "mm", format: "a4" });
  const stamp = format(new Date(), "yyyy-MM-dd");
  const projection = computeInvestorScenarioProjection(roiInputs);
  const roi = computeInvestorRoi(roiInputs);
  const revenueSharing = computeInvestorRevenueSharing(roiInputs);
  const scenarios = buildInvestorRoiScenarioRows();
  const ownerPct = 100 - roiInputs.investorEquityPct;
  let y = 14;

  doc.setFillColor(26, 82, 150);
  doc.rect(0, 0, 210, 24, "F");
  doc.setTextColor(255, 255, 255);
  doc.setFontSize(14);
  doc.setFont("helvetica", "bold");
  doc.text(INVESTOR_PLAN_META.title, 14, 10);
  doc.setFontSize(9);
  doc.setFont("helvetica", "normal");
  doc.text(`${INVESTOR_PLAN_META.product} · ${stamp}`, 14, 17);
  doc.setTextColor(0, 0, 0);

  y = 32;
  doc.setFontSize(10);
  doc.text(
    `Capital ${fmtInvestorXof(INVESTOR_CAPITAL.totalXof)} · Apport investisseur ${fmtInvestorXof(INVESTOR_PLAN_LEVEE.amountXof)} · ${projection.scenario.label}`,
    14,
    y,
  );
  y += 8;
  doc.text(
    `Production : ${INVESTOR_PLAN_META.url} · Hypothèses en ${INVESTOR_PLAN_META.currency}`,
    14,
    y,
  );
  y += 10;

  y = addSectionTitle(doc, "Actionnariat", y);
  autoTable(doc, {
    startY: y,
    head: [INVESTOR_CAPITAL_TABLE.headers],
    body: INVESTOR_CAPITAL_TABLE.rows,
    styles: { fontSize: 8 },
    headStyles: { fillColor: [26, 82, 150] },
    margin: { left: 14, right: 14 },
  });
  y = (doc as jsPDF & { lastAutoTable?: { finalY: number } }).lastAutoTable?.finalY ?? y + 40;
  y += 8;

  y = addSectionTitle(doc, `Projection financière — ${projection.scenario.label}`, y);
  autoTable(doc, {
    startY: y,
    head: [
      [
        "Année",
        "Billets/mois",
        "GMV",
        `Rev. plateforme (${roiInputs.tibusTakeRatePct} %)`,
        "OPEX",
        "Résultat net",
        `Invest. ${roiInputs.investorEquityPct} %`,
        `Porteur ${ownerPct} %`,
      ],
    ],
    body: projection.years.map((row) => [
      row.yearLabel,
      row.ticketsMonth.toLocaleString("fr-FR"),
      fmtInvestorXof(row.gmv),
      fmtInvestorXof(row.tibusRevenue),
      fmtInvestorXof(row.opex),
      fmtInvestorXof(row.netResult),
      fmtInvestorXof(row.investorShare),
      fmtInvestorXof(row.ownerShare),
    ]),
    styles: { fontSize: 7 },
    headStyles: { fillColor: [26, 82, 150] },
    margin: { left: 14, right: 14 },
  });
  y = (doc as jsPDF & { lastAutoTable?: { finalY: number } }).lastAutoTable?.finalY ?? y + 40;
  y += 8;

  if (y > 220) {
    doc.addPage();
    y = 20;
  }

  y = addSectionTitle(doc, "Revenue sharing associés — 40 % / 60 % du revenu plateforme", y);
  autoTable(doc, {
    startY: y,
    head: [
      [
        "Période",
        "Revenu plateforme (100 %)",
        "Taux invest.",
        "Versement invest.",
        "Taux porteur",
        "Versement porteur",
        "Cumulé invest.",
        "Récup.",
      ],
    ],
    body: [
      [
        "Investissement (T0)",
        "—",
        "—",
        fmtInvestorXof(-(revenueSharing.investment ?? 0)),
        "—",
        "—",
        fmtInvestorXof(-(revenueSharing.investment ?? 0)),
        "—",
      ],
      ...revenueSharing.years.map((row) => [
        row.label,
        fmtInvestorXof(row.platformRevenue),
        `${row.investorShareRate} %`,
        fmtInvestorXof(row.annualPayout),
        `${row.ownerShareRate} %`,
        fmtInvestorXof(row.ownerPayout),
        fmtInvestorXof(row.cumulativeNet),
        row.recoveryPct != null ? `${row.recoveryPct.toFixed(1)} %` : "—",
      ]),
    ],
    styles: { fontSize: 8 },
    headStyles: { fillColor: [26, 82, 150] },
    margin: { left: 14, right: 14 },
  });
  y = (doc as jsPDF & { lastAutoTable?: { finalY: number } }).lastAutoTable?.finalY ?? y + 40;
  y += 8;

  if (y > 250) {
    doc.addPage();
    y = 20;
  }

  y = addSectionTitle(doc, "Comparaison scénarios (5 ans)", y);
  autoTable(doc, {
    startY: y,
    head: [scenarios.headers],
    body: scenarios.rows,
    styles: { fontSize: 8 },
    headStyles: { fillColor: [26, 82, 150] },
    margin: { left: 14, right: 14 },
  });
  y = (doc as jsPDF & { lastAutoTable?: { finalY: number } }).lastAutoTable?.finalY ?? y + 40;
  y += 8;

  if (y > 250) {
    doc.addPage();
    y = 20;
  }

  y = addSectionTitle(doc, "Simulateur — hypothèses saisies", y);
  autoTable(doc, {
    startY: y,
    head: [["Indicateur", "Valeur"]],
    body: [
      ["Scénario", INVESTOR_SCENARIOS[roiInputs.scenarioId].label],
      ["Panier moyen", fmtInvestorXof(roiInputs.avgTicket)],
      ["Take rate plateforme", `${roiInputs.tibusTakeRatePct} %`],
      ["Multiplicateur volume", `${roiInputs.volumeMultiplierPct} %`],
      ["Montant investi", fmtInvestorXof(roiInputs.investmentXof)],
      ["Part investisseur", `${roiInputs.investorEquityPct} %`],
      ["Part porteur", `${ownerPct} %`],
      ["Horizon", `${roiInputs.horizonYears} an(s)`],
      ["GMV dernière année", fmtInvestorXof(roi.gmvYear)],
      ["Revenu plateforme dernière année", fmtInvestorXof(roi.revTotal)],
      ["Résultat net dernière année", fmtInvestorXof(roi.netYear)],
      ["Cumul part investisseur", fmtInvestorXof(roi.cumulativeInvestorShare)],
      ["ROI", fmtInvestorMultiple(roi.roi)],
      ["TRI annualisé", fmtInvestorPercent(roi.irr)],
      ["Gain net", fmtInvestorXof(roi.gain)],
    ],
    styles: { fontSize: 8 },
    headStyles: { fillColor: [26, 82, 150] },
    margin: { left: 14, right: 14 },
  });

  doc.save(`tibus-plan-investisseur-${stamp}.pdf`);
}

export function downloadInvestorPlanJson(roiInputs: InvestorRoiInputs) {
  const stamp = format(new Date(), "yyyy-MM-dd");
  const payload = {
    generatedAt: new Date().toISOString(),
    meta: INVESTOR_PLAN_META,
    capital: INVESTOR_CAPITAL,
    levee: INVESTOR_PLAN_LEVEE,
    scenarios: INVESTOR_SCENARIOS,
    roiScenarios: buildInvestorRoiScenarioRows(),
    simulator: {
      inputs: roiInputs,
      projection: computeInvestorScenarioProjection(roiInputs),
      results: computeInvestorRoi(roiInputs),
      revenueSharing: computeInvestorRevenueSharing(roiInputs),
    },
  };
  const blob = new Blob([JSON.stringify(payload, null, 2)], { type: "application/json" });
  const url = URL.createObjectURL(blob);
  const anchor = document.createElement("a");
  anchor.href = url;
  anchor.download = `tibus-plan-investisseur-${stamp}.json`;
  anchor.click();
  URL.revokeObjectURL(url);
}
