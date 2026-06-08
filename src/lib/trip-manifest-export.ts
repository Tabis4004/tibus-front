import { format } from "date-fns";
import jsPDF from "jspdf";
import autoTable from "jspdf-autotable";
import type { TripManifest } from "@/lib/supabase/owner-reports";

const MANIFEST_HEADERS = [
  "Nom du passager",
  "Numéro de billet",
  "Gare de départ",
  "Nombre de colis/bagages",
  "Statut de la réservation",
] as const;

function manifestRows(manifest: TripManifest) {
  return manifest.passengers.map((row) => [
    row.passengerName,
    row.ticketNumber,
    row.departureStation,
    String(row.parcelCount),
    row.reservationStatus,
  ]);
}

function manifestFileSlug(manifest: TripManifest) {
  const datePart = format(new Date(manifest.departureTime), "yyyy-MM-dd_HHmm");
  return `manifeste-${datePart}`;
}

export function exportTripManifestExcel(manifest: TripManifest) {
  const meta = [
    ["Compagnie", manifest.companyName],
    ["Trajet", manifest.routeLabel],
    ["Départ", format(new Date(manifest.departureTime), "dd/MM/yyyy HH:mm")],
    ["Bus", `${manifest.busName} (${manifest.busPlateNumber})`],
    ["Gare de départ", manifest.departureStation],
    [],
    [...MANIFEST_HEADERS],
    ...manifestRows(manifest),
  ];

  const csvContent = meta
    .map((row) => row.map((cell) => `"${String(cell).replace(/"/g, '""')}"`).join(","))
    .join("\n");

  const blob = new Blob(["\uFEFF" + csvContent], {
    type: "text/csv;charset=utf-8;",
  });
  const link = document.createElement("a");
  link.href = URL.createObjectURL(blob);
  link.download = `${manifestFileSlug(manifest)}.csv`;
  link.click();
  URL.revokeObjectURL(link.href);
}

export function exportTripManifestPDF(manifest: TripManifest) {
  const doc = new jsPDF({ orientation: "portrait", unit: "mm", format: "a4" });

  doc.setFillColor(75, 0, 130);
  doc.rect(0, 0, 210, 22, "F");
  doc.setTextColor(255, 255, 255);
  doc.setFontSize(14);
  doc.setFont("helvetica", "bold");
  doc.text("Manifeste passagers", 14, 10);
  doc.setFontSize(9);
  doc.setFont("helvetica", "normal");
  doc.text(manifest.companyName, 14, 16);

  doc.setTextColor(0, 0, 0);
  doc.setFontSize(10);
  doc.text(`Trajet : ${manifest.routeLabel}`, 14, 30);
  doc.text(
    `Départ : ${format(new Date(manifest.departureTime), "dd/MM/yyyy HH:mm")}`,
    14,
    36,
  );
  doc.text(`Bus : ${manifest.busName} (${manifest.busPlateNumber})`, 14, 42);
  doc.text(`Gare de départ : ${manifest.departureStation}`, 14, 48);
  doc.text(`Passagers : ${manifest.passengers.length}`, 14, 54);

  autoTable(doc, {
    startY: 60,
    head: [[...MANIFEST_HEADERS]],
    body: manifestRows(manifest),
    theme: "striped",
    styles: { fontSize: 8, cellPadding: 2 },
    headStyles: { fillColor: [75, 0, 130], fontSize: 8, fontStyle: "bold" },
    alternateRowStyles: { fillColor: [248, 248, 252] },
  });

  const finalY = (doc as unknown as { lastAutoTable: { finalY: number } }).lastAutoTable.finalY + 8;
  doc.setFontSize(7);
  doc.text(`Généré le ${format(new Date(), "dd/MM/yyyy HH:mm")} — Powered By Tibus`, 14, finalY);

  doc.save(`${manifestFileSlug(manifest)}.pdf`);
}
