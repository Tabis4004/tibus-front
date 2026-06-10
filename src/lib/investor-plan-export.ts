import { format } from "date-fns";
import jsPDF from "jspdf";
import autoTable from "jspdf-autotable";
import {
  buildInvestorRoiScenarioRows,
  computeInvestorFinancials,
  computeInvestorRevenueSharing,
  computeInvestorRoi,
  fmtInvestorMultiple,
  fmtInvestorPercent,
  fmtInvestorXof,
  INVESTOR_PLAN_LEVEE,
  INVESTOR_PLAN_META,
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
  const financials = computeInvestorFinancials();
  const base = financials[3];
  const roi = computeInvestorRoi(roiInputs);
  const revenueSharing = computeInvestorRevenueSharing(roiInputs);
  const scenarios = buildInvestorRoiScenarioRows();
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
    `Levée cible : ${fmtInvestorXof(INVESTOR_PLAN_LEVEE.amountXof)} · GMV An 3 : ${fmtInvestorXof(base.gmvYear)} · Revenu An 3 : ${fmtInvestorXof(base.revTotal)}`,
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

  y = addSectionTitle(doc, "Projections financières (scénario base)", y);
  autoTable(doc, {
    startY: y,
    head: [["Année", "Compagnies", "Billets/mois", "GMV annuel", "Rev. total", "EBITDA"]],
    body: financials.map((row) => [
      row.year,
      String(row.companies),
      fmtInvestorXof(row.ticketsMonth, ""),
      fmtInvestorXof(row.gmvYear),
      fmtInvestorXof(row.revTotal),
      fmtInvestorXof(row.ebitda),
    ]),
    styles: { fontSize: 8 },
    headStyles: { fillColor: [26, 82, 150] },
    margin: { left: 14, right: 14 },
  });
  y = (doc as jsPDF & { lastAutoTable?: { finalY: number } }).lastAutoTable?.finalY ?? y + 40;
  y += 8;

  y = addSectionTitle(doc, "ROI investisseur (scénarios)", y);
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

  if (y > 220) {
    doc.addPage();
    y = 20;
  }

  y = addSectionTitle(doc, "Revenue sharing (3 ans)", y);
  autoTable(doc, {
    startY: y,
    head: [
      [
        "Période",
        "Revenu plateforme",
        "Taux share",
        "Versement",
        "Cumulé",
        "Récup. invest.",
      ],
    ],
    body: [
      [
        "Investissement (T0)",
        "—",
        "—",
        fmtInvestorXof(-(revenueSharing.investment ?? 0)),
        fmtInvestorXof(-(revenueSharing.investment ?? 0)),
        "—",
      ],
      ...revenueSharing.years.map((row) => [
        row.label,
        fmtInvestorXof(row.platformRevenue),
        `${revenueSharing.revenueSharePct} %`,
        fmtInvestorXof(row.annualPayout),
        fmtInvestorXof(row.cumulativeNet),
        row.recoveryPct != null ? `${row.recoveryPct.toFixed(1)} %` : "—",
      ]),
      [
        `Sortie (${revenueSharing.equityPct} % × ${revenueSharing.exitMultiple}×)`,
        fmtInvestorXof(revenueSharing.years.at(-1)?.platformRevenue ?? 0),
        `${revenueSharing.equityPct} %`,
        fmtInvestorXof(revenueSharing.exitStake),
        fmtInvestorXof(
          revenueSharing.totalReturn - (revenueSharing.investment ?? 0),
        ),
        fmtInvestorMultiple(revenueSharing.totalRoi),
      ],
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

  y = addSectionTitle(doc, "Simulateur ROI (hypothèses saisies)", y);
  autoTable(doc, {
    startY: y,
    head: [["Indicateur", "Valeur"]],
    body: [
      ["Compagnies actives", String(roiInputs.companies)],
      ["Billets / mois", String(roiInputs.ticketsMonth)],
      ["Panier moyen", fmtInvestorXof(roiInputs.avgTicket)],
      ["Take rate net", `${roiInputs.takeRatePct} %`],
      ["Abonnement / compagnie / mois", fmtInvestorXof(roiInputs.aboMonth)],
      ["Montant investi", fmtInvestorXof(roiInputs.investmentXof)],
      ["Part capital", `${roiInputs.equityPct} %`],
      ["Revenue share", `${roiInputs.revenueSharePct} %`],
      ["Multiple de sortie", fmtInvestorMultiple(roiInputs.exitMultiple)],
      ["Horizon", `${roiInputs.horizonYears} an(s)`],
      ["GMV annuel", fmtInvestorXof(roi.gmvYear)],
      ["Revenu total", fmtInvestorXof(roi.revTotal)],
      ["Valorisation sortie", fmtInvestorXof(roi.exitValuation)],
      ["Valeur part", fmtInvestorXof(roi.stakeValue)],
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
    levee: INVESTOR_PLAN_LEVEE,
    financials: computeInvestorFinancials(),
    roiScenarios: buildInvestorRoiScenarioRows(),
    simulator: {
      inputs: roiInputs,
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
