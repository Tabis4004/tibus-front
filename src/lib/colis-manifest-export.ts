import { format } from "date-fns";
import jsPDF from "jspdf";
import autoTable from "jspdf-autotable";
import type { ColisAutonomeRow } from "@/lib/supabase/colis-autonomes";
import { COLIS_STATUT_LABELS } from "@/lib/supabase/colis-autonomes";

export type ColisManifestMeta = {
  companyName: string;
  /** Libellé du filtre appliqué (ex. « Tous les statuts », « Enregistré »). */
  filterLabel: string;
};

const COLIS_HEADERS = [
  "Date",
  "Réf.",
  "Gare départ",
  "Gare destination",
  "Expéditeur",
  "Tél. exp.",
  "Destinataire",
  "Tél. dest.",
  "Nature(s)",
  "Bus",
  "Contenu",
  "Poids (kg)",
  "Pièces",
  "Montant",
  "Statut",
] as const;

function colisRef(row: ColisAutonomeRow): string {
  return `CL-${row.id.slice(0, 8).toUpperCase()}`;
}

function colisRows(rows: ColisAutonomeRow[]) {
  return rows.map((row) => [
    format(new Date(row.createdAt), "dd/MM/yy HH:mm"),
    colisRef(row),
    row.gareDepart,
    row.gareDestination,
    row.nomExpediteur,
    row.telephoneExpediteur,
    row.nomDestinataire,
    row.telephoneDestinataire,
    row.natures.join(", "),
    row.busPlateNumber ?? "",
    row.descriptionContenu ?? "",
    row.poidsKg != null ? String(row.poidsKg) : "",
    String(row.nombrePieces),
    row.montantFret.toLocaleString(),
    COLIS_STATUT_LABELS[row.statutColis] ?? row.statutColis,
  ]);
}

function fileSlug() {
  return `manifeste-colis-${format(new Date(), "yyyy-MM-dd_HHmm")}`;
}

export function exportColisManifestExcel(rows: ColisAutonomeRow[], meta: ColisManifestMeta) {
  const total = rows.reduce((sum, row) => sum + row.montantFret, 0);
  const content = [
    ["Compagnie", meta.companyName],
    ["Manifeste", "Envois de colis autonomes"],
    ["Filtre", meta.filterLabel],
    ["Édité le", format(new Date(), "dd/MM/yyyy HH:mm")],
    ["Nombre d'envois", String(rows.length)],
    ["Total fret", total.toLocaleString()],
    [],
    [...COLIS_HEADERS],
    ...colisRows(rows),
  ];

  const csv = content
    .map((row) => row.map((cell) => `"${String(cell).replace(/"/g, '""')}"`).join(","))
    .join("\n");

  const blob = new Blob(["﻿" + csv], { type: "text/csv;charset=utf-8;" });
  const link = document.createElement("a");
  link.href = URL.createObjectURL(blob);
  link.download = `${fileSlug()}.csv`;
  link.click();
  URL.revokeObjectURL(link.href);
}

export function exportColisManifestPDF(rows: ColisAutonomeRow[], meta: ColisManifestMeta) {
  const doc = new jsPDF({ orientation: "landscape", unit: "mm", format: "a4" });
  const total = rows.reduce((sum, row) => sum + row.montantFret, 0);

  doc.setFillColor(75, 0, 130);
  doc.rect(0, 0, 297, 22, "F");
  doc.setTextColor(255, 255, 255);
  doc.setFontSize(14);
  doc.setFont("helvetica", "bold");
  doc.text("Manifeste colis autonomes", 14, 10);
  doc.setFontSize(9);
  doc.setFont("helvetica", "normal");
  doc.text(meta.companyName, 14, 16);

  doc.setTextColor(0, 0, 0);
  doc.setFontSize(10);
  doc.text(`Filtre : ${meta.filterLabel}`, 14, 30);
  doc.text(`Envois : ${rows.length} · Total fret : ${total.toLocaleString()}`, 14, 36);

  autoTable(doc, {
    startY: 42,
    head: [[...COLIS_HEADERS]],
    body: colisRows(rows),
    theme: "striped",
    styles: { fontSize: 6.5, cellPadding: 1.5, overflow: "linebreak" },
    headStyles: { fillColor: [75, 0, 130], fontSize: 6.5, fontStyle: "bold" },
    alternateRowStyles: { fillColor: [248, 248, 252] },
  });

  const finalY =
    (doc as unknown as { lastAutoTable: { finalY: number } }).lastAutoTable.finalY + 8;
  doc.setFontSize(7);
  doc.text(`Généré le ${format(new Date(), "dd/MM/yyyy HH:mm")} — Powered By Tibus`, 14, finalY);

  doc.save(`${fileSlug()}.pdf`);
}
