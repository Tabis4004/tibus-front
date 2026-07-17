import { toast } from "sonner";
import { printer, type PrintLine } from "@/lib/printer.ts";
import type { ColisAutonomeDetail } from "@/lib/supabase/colis-autonomes.ts";
import { COLIS_STATUT_LABELS } from "@/lib/supabase/colis-autonomes.ts";
import { readTibusBridgeFlags } from "@/lib/webview-bridge.ts";
import type { ThermalPaperWidth } from "@/lib/ticket-receipt-print.ts";
import { RECEIPT_POWERED_BY_LINE } from "@/lib/receipt-branding.ts";

export function colisPublicReference(colisId: string): string {
  const compact = colisId.replace(/-/g, "").toUpperCase();
  return `CL-${compact.slice(0, 8)}`;
}

/**
 * Numéro affiché sur le reçu : numérotation séquentielle par gare de départ
 * (ex. ABOI000001, migration 180) si disponible, sinon repli CL-XXXXXXXX.
 * resolve_colis_retrait_code accepte les deux formats (migration 181).
 */
export function colisReceiptNumber(detail: Pick<ColisAutonomeDetail, "id" | "numeroRecu">): string {
  return detail.numeroRecu?.trim() || colisPublicReference(detail.id);
}

export function colisQrPayload(detail: ColisAutonomeDetail): string {
  return colisPublicReference(detail.id);
}

export type ColisReceiptInput = {
  detail: ColisAutonomeDetail;
  currency?: string;
};

type TibusP3Bridge = {
  printReceipt58?: (title: string, payload: string) => void;
  printReceipt80?: (title: string, payload: string) => void;
};

function tibusP3(): TibusP3Bridge | undefined {
  if (typeof window === "undefined") return undefined;
  return (window as unknown as Record<string, unknown>).TibusP3 as TibusP3Bridge | undefined;
}

export function buildColisReceiptLines(detail: ColisAutonomeDetail, currency: string): PrintLine[] {
  const ref = colisReceiptNumber(detail);
  const natureLabel = detail.natures.filter(Boolean).join(", ") || "—";
  const description = detail.descriptionContenu?.trim() || "—";

  return [
    { text: "RECU EXPEDITION COLIS", align: "center", bold: true },
    { text: "Code de retrait — presentez a la gare destination", align: "center", size: "small" },
    { text: "" },
    { text: `Ref: ${ref}`, align: "center", bold: true, size: "large" },
    { text: `Statut: ${COLIS_STATUT_LABELS[detail.statutColis]}` },
    { text: "" },
    { text: `Depart: ${detail.gareDepart}`, bold: true },
    { text: `Destination: ${detail.gareDestination}`, bold: true },
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
    { text: `Description: ${description}` },
    { text: `Pieces: ${detail.nombrePieces}` },
    { text: detail.poidsKg ? `Poids: ${detail.poidsKg} kg` : "Poids: —" },
    { text: "" },
    { text: `Montant fret: ${detail.montantFret.toLocaleString()} ${currency}`, bold: true },
    ...(detail.valeurMarchandise != null && detail.valeurMarchandise > 0
      ? [{ text: `Valeur marchandise: ${detail.valeurMarchandise.toLocaleString()} ${currency}` }]
      : []),
    ...(detail.pourcentagePercu != null && detail.pourcentagePercu > 0
      ? [{ text: `Pourcentage percu: ${detail.pourcentagePercu}%` }]
      : []),
    { text: "" },
    { text: "Scannez le QR ou saisissez la reference CL- au retrait.", align: "center", size: "small" },
    { text: RECEIPT_POWERED_BY_LINE, align: "center", size: "small" },
  ];
}

function printViaTibusP3(
  detail: ColisAutonomeDetail,
  lines: PrintLine[],
  paperWidth: ThermalPaperWidth,
  companyName: string,
): boolean {
  const p3 = tibusP3();
  if (!p3?.printReceipt58 && !p3?.printReceipt80) return false;

  const qr = colisQrPayload(detail);
  const payload = JSON.stringify({
    title: companyName,
    text: lines.map((line) => line.text).join("\n"),
    qr,
    reference: qr,
    score: 999,
    source: "colis-receipt",
    kind: "colis",
  });

  if (paperWidth === "80mm" && p3.printReceipt80) {
    p3.printReceipt80(companyName, payload);
    return true;
  }
  if (p3.printReceipt58) {
    p3.printReceipt58(companyName, payload);
    return true;
  }
  if (p3.printReceipt80) {
    p3.printReceipt80(companyName, payload);
    return true;
  }
  return false;
}

export function printColisReceiptBrowser(paperWidth: ThermalPaperWidth = "80mm"): void {
  const htmlEl = document.documentElement;
  htmlEl.classList.remove("print-80mm", "print-56mm");
  htmlEl.classList.add(paperWidth === "56mm" ? "print-56mm" : "print-80mm");
  window.print();
  window.setTimeout(() => htmlEl.classList.remove("print-80mm", "print-56mm"), 1000);
}

export function printColisReceipt(
  detail: ColisAutonomeDetail,
  currency = "XOF",
  paperWidth: ThermalPaperWidth = "80mm",
  companyName?: string,
): void {
  const resolvedName = companyName || detail.companyName || "TIBUS COLIS";
  const lines = buildColisReceiptLines(detail, currency);
  const qr = colisQrPayload(detail);
  try {
    if (printViaTibusP3(detail, lines, paperWidth, resolvedName)) return;
    if (printer.isNative) {
      void printer.printReceipt({
        header: resolvedName,
        lines,
        qr,
        qrSize: 220,
        feedLines: 4,
        cut: true,
      });
      return;
    }
    printColisReceiptBrowser(paperWidth);
  } catch (error) {
    console.error("Colis print error:", error);
    toast.error("Impression impossible");
  }
}

/** Construit un lien wa.me pré-rempli pour un numéro et un message donnés. */
export function buildColisWhatsAppLink(phone: string, message: string): string {
  const digits = phone.replace(/\D/g, "");
  return `https://wa.me/${digits}?text=${encodeURIComponent(message)}`;
}

export function openColisWhatsApp(phone: string, message: string): void {
  if (!phone.trim()) {
    toast.error("Numéro de téléphone manquant");
    return;
  }
  window.open(buildColisWhatsAppLink(phone, message), "_blank", "noopener,noreferrer");
}

/** Message WhatsApp de suivi — même contenu informatif que le SMS, pour envoi manuel à chaque étape. */
export function buildColisTrackingWhatsAppMessage(input: {
  colisId: string;
  statut: ColisAutonomeDetail["statutColis"];
  companyName: string;
  gareDepart: string;
  gareDestination: string;
  recipientLabel: "Expéditeur" | "Destinataire";
}): string {
  const ref = colisPublicReference(input.colisId);
  return [
    `${input.companyName} — Suivi colis ${ref}`,
    `Statut : ${COLIS_STATUT_LABELS[input.statut]}`,
    `Trajet : ${input.gareDepart} → ${input.gareDestination}`,
    `Bonjour, votre colis (réf. ${ref}) est maintenant "${COLIS_STATUT_LABELS[input.statut]}".`,
  ].join("\n");
}

export function isColisPosPrinterAvailable(): boolean {
  const flags = readTibusBridgeFlags();
  return (
    flags.tibusP3 ||
    flags.wisePrinter ||
    Boolean(tibusP3()?.printReceipt58 || tibusP3()?.printReceipt80)
  );
}
