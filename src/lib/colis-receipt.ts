import { printer, type PrintLine } from "@/lib/printer.ts";
import type { ColisAutonomeDetail } from "@/lib/supabase/colis-autonomes.ts";
import { COLIS_STATUT_LABELS } from "@/lib/supabase/colis-autonomes.ts";

export function colisPublicReference(colisId: string): string {
  const compact = colisId.replace(/-/g, "").toUpperCase();
  return `CL-${compact.slice(0, 8)}`;
}

type TibusP3Bridge = {
  printReceipt58?: (title: string, payload: string) => void;
  printReceipt80?: (title: string, payload: string) => void;
};

function tibusP3(): TibusP3Bridge | undefined {
  if (typeof window === "undefined") return undefined;
  return (window as unknown as Record<string, unknown>).TibusP3 as TibusP3Bridge | undefined;
}

function buildColisReceiptLines(detail: ColisAutonomeDetail, currency: string): PrintLine[] {
  const ref = colisPublicReference(detail.id);
  const natureLabel = detail.natures[0] ?? "—";

  return [
    { text: "RECU EXPEDITION COLIS", align: "center", bold: true },
    { text: "CONFIDENTIEL — CODE RETRAIT", align: "center", size: "small" },
    { text: "" },
    { text: `Ref: ${ref}`, bold: true },
    { text: `Code retrait:`, bold: true },
    { text: detail.id, align: "center", size: "large", bold: true },
    { text: "" },
    { text: `Statut: ${COLIS_STATUT_LABELS[detail.statutColis]}` },
    { text: `Depart: ${detail.gareDepart}` },
    { text: `Destination: ${detail.gareDestination}` },
    { text: "" },
    { text: "EXPEDITEUR", bold: true },
    { text: detail.nomExpediteur },
    { text: detail.telephoneExpediteur, size: "small" },
    { text: "" },
    { text: "DESTINATAIRE", bold: true },
    { text: detail.nomDestinataire },
    { text: detail.telephoneDestinataire, size: "small" },
    { text: "" },
    { text: `Nature: ${natureLabel}`, bold: true },
    { text: `Pieces: ${detail.nombrePieces}` },
    { text: detail.poidsKg ? `Poids: ${detail.poidsKg} kg` : "Poids: —" },
    { text: detail.descriptionContenu ? `Contenu: ${detail.descriptionContenu}` : "" },
    { text: "" },
    { text: `Montant fret: ${detail.montantFret.toLocaleString()} ${currency}`, bold: true },
    { text: "" },
    { text: "Scannez le QR ou presentez ce code a la gare de destination.", align: "center", size: "small" },
  ];
}

function printViaTibusP3(detail: ColisAutonomeDetail, lines: PrintLine[]): boolean {
  const p3 = tibusP3();
  if (!printer.isNative || !p3) return false;

  const payload = JSON.stringify({
    title: detail.companyName || "TIBUS COLIS",
    text: lines.map((line) => line.text).join("\n"),
    qr: detail.id,
    score: 999,
    source: "colis-receipt",
  });

  if (p3.printReceipt80) {
    p3.printReceipt80(detail.companyName || "TIBUS COLIS", payload);
    return true;
  }
  if (p3.printReceipt58) {
    p3.printReceipt58(detail.companyName || "TIBUS COLIS", payload);
    return true;
  }
  return false;
}

export async function printColisReceipt(detail: ColisAutonomeDetail, currency = "XOF") {
  const lines = buildColisReceiptLines(detail, currency);

  if (printViaTibusP3(detail, lines)) return;

  await printer.printReceipt({
    header: detail.companyName || "TIBUS COLIS",
    lines,
    qr: detail.id,
    qrSize: 220,
    feedLines: 4,
    cut: true,
  });
}
