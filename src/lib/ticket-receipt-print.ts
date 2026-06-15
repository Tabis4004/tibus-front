import { format, parseISO } from "date-fns";
import { toast } from "sonner";
import { toPng } from "html-to-image";
import { printer, type PrintLine } from "@/lib/printer.ts";
import {
  generateReceiptPDF,
  type ReceiptData,
  type ReceiptFormat,
} from "@/lib/receipt-pdf.ts";
import { buildTicketVerifyUrl } from "@/lib/ticket-verify-url.ts";

export type SellerCompanyReceiptInfo = {
  name: string;
  logoUrl?: string | null;
  phone?: string;
  email?: string;
  address?: string;
  nif?: string;
  rccm?: string;
  tva?: string;
  bankAccount?: string;
  boardingMessage?: string;
};

export type TicketReceiptParcel = {
  count: number;
  weight: number;
  amount: number;
};

export type TicketReceiptTrip = {
  originCity: string;
  originStation?: string;
  destCity: string;
  destStation?: string;
  departureTime: string;
  arrivalTime?: string;
  priceAmount: number;
  currency: string;
  busName?: string;
  busPlateNumber?: string;
  busType?: string;
};

export type TicketReceiptInput = {
  reference: string;
  verifyToken?: string | null;
  passengerName: string;
  passengerPhone?: string;
  seatNumber?: string | null;
  totalPrice: number;
  parcel?: TicketReceiptParcel | null;
  trip: TicketReceiptTrip;
  companyName: string;
  companyInfo?: SellerCompanyReceiptInfo;
  boardingMessage?: string;
  lng?: string;
};

export type ThermalPaperWidth = "80mm" | "56mm";

type TibusP3Bridge = {
  printReceipt58?: (title: string, payload: string) => void;
  printReceipt80?: (title: string, payload: string) => void;
};

function fmt(iso: string, pattern: string): string {
  try {
    return format(parseISO(iso), pattern);
  } catch {
    return iso;
  }
}

function separator(paperWidth: ThermalPaperWidth): string {
  return paperWidth === "56mm" ? "------------------------------" : "----------------------------------------";
}

function tibusP3(): TibusP3Bridge | undefined {
  if (typeof window === "undefined") return undefined;
  return (window as unknown as Record<string, unknown>).TibusP3 as TibusP3Bridge | undefined;
}

export function isPosPrinterAvailable(): boolean {
  return printer.isNative && Boolean(tibusP3()?.printReceipt58 || tibusP3()?.printReceipt80);
}

function buildVerifyUrl(input: TicketReceiptInput): string {
  return buildTicketVerifyUrl({
    reference: input.reference,
    verifyToken: input.verifyToken,
    lng: input.lng,
  });
}

export function buildTicketReceiptLines(
  input: TicketReceiptInput,
  paperWidth: ThermalPaperWidth = "80mm",
): PrintLine[] {
  const sep = separator(paperWidth);
  const companyInfo = input.companyInfo;
  const companyName = input.companyName || companyInfo?.name || "Tibus";
  const parcel = input.parcel;
  const lines: PrintLine[] = [{ text: companyName, align: "center", size: "large", bold: true }];

  if (companyInfo?.address) lines.push({ text: companyInfo.address, align: "center", size: "small" });
  if (companyInfo?.phone || companyInfo?.email) {
    lines.push({
      text: [companyInfo.phone, companyInfo.email].filter(Boolean).join(" | "),
      align: "center",
      size: "small",
    });
  }
  if (companyInfo?.nif || companyInfo?.rccm) {
    lines.push({
      text: [
        companyInfo.nif ? `NIF:${companyInfo.nif}` : "",
        companyInfo.rccm ? `RCCM:${companyInfo.rccm}` : "",
      ]
        .filter(Boolean)
        .join(" "),
      align: "center",
      size: "small",
    });
  }
  if (companyInfo?.tva) lines.push({ text: `TVA: ${companyInfo.tva}`, align: "center", size: "small" });
  if (companyInfo?.bankAccount) {
    lines.push({ text: `Compte: ${companyInfo.bankAccount}`, align: "center", size: "small" });
  }

  lines.push(
    { text: sep },
    { text: "Reference", align: "center", bold: true, size: "small" },
    { text: input.reference, align: "center", size: "large", bold: true },
    { text: sep },
    { text: `Voyageur: ${input.passengerName}` },
  );
  if (input.passengerPhone) lines.push({ text: `Telephone: ${input.passengerPhone}` });
  if (input.seatNumber) lines.push({ text: `Siege: #${input.seatNumber}`, bold: true });

  lines.push(
    { text: sep },
    {
      text: `Trajet: ${input.trip.originCity} -> ${input.trip.destCity}`,
      bold: true,
    },
    { text: `Depart: ${fmt(input.trip.departureTime, "dd/MM/yyyy HH:mm")}` },
  );
  if (input.trip.arrivalTime) {
    lines.push({ text: `Arrivee: ${fmt(input.trip.arrivalTime, "dd/MM/yyyy HH:mm")}` });
  }
  if (input.trip.busName || input.trip.busPlateNumber) {
    lines.push({
      text: `Bus: ${[input.trip.busName, input.trip.busPlateNumber].filter(Boolean).join(" - ")}`,
    });
  }

  lines.push(
    { text: sep },
    { text: `Prix ticket: ${input.trip.currency} ${input.trip.priceAmount.toLocaleString()}` },
  );

  if (parcel && parcel.count > 0) {
    lines.push({ text: `Colis: ${parcel.count}` });
    if (parcel.weight > 0) lines.push({ text: `Poids: ${parcel.weight} Kg` });
    if (parcel.amount > 0) {
      lines.push({ text: `Montant colis: ${input.trip.currency} ${parcel.amount.toLocaleString()}` });
    }
  }

  lines.push(
    { text: sep },
    {
      text: `Total: ${input.trip.currency} ${input.totalPrice.toLocaleString()}`,
      bold: true,
      size: "large",
    },
    { text: `Date: ${format(new Date(), "dd/MM/yyyy HH:mm")}`, size: "small" },
  );

  const boarding = input.boardingMessage ?? companyInfo?.boardingMessage;
  if (boarding) {
    lines.push({ text: sep }, { text: `! ${boarding}`, size: "small" });
  }

  lines.push({ text: sep }, { text: "Powered By Tibus", align: "center", size: "small" });
  return lines;
}

function printViaTibusP3(
  input: TicketReceiptInput,
  lines: PrintLine[],
  paperWidth: ThermalPaperWidth,
): boolean {
  const p3 = tibusP3();
  if (!printer.isNative || !p3) return false;

  const payload = JSON.stringify({
    title: input.companyName || input.companyInfo?.name || "Tibus",
    text: lines.map((line) => line.text).join("\n"),
    qr: buildVerifyUrl(input),
    score: 999,
    source: "seller-ui",
  });

  if (paperWidth === "80mm" && p3.printReceipt80) {
    p3.printReceipt80(input.companyName, payload);
    return true;
  }
  if (p3.printReceipt58) {
    p3.printReceipt58(input.companyName, payload);
    return true;
  }
  if (p3.printReceipt80) {
    p3.printReceipt80(input.companyName, payload);
    return true;
  }
  return false;
}

export function printTicketReceiptBrowser(paperWidth: ThermalPaperWidth = "80mm"): void {
  const htmlEl = document.documentElement;
  htmlEl.classList.remove("print-80mm", "print-56mm");
  htmlEl.classList.add(paperWidth === "56mm" ? "print-56mm" : "print-80mm");
  window.print();
  window.setTimeout(() => htmlEl.classList.remove("print-80mm", "print-56mm"), 1000);
}

export function printTicketReceipt(
  input: TicketReceiptInput,
  paperWidth: ThermalPaperWidth = "80mm",
): void {
  const lines = buildTicketReceiptLines(input, paperWidth);
  try {
    if (printViaTibusP3(input, lines, paperWidth)) return;
    printTicketReceiptBrowser(paperWidth);
  } catch (error) {
    console.error("Print error:", error);
    toast.error("Impression impossible");
  }
}

export function buildTicketReceiptPdfData(input: TicketReceiptInput): ReceiptData {
  const companyInfo = input.companyInfo;
  const parcel = input.parcel;
  return {
    bookingReference: input.reference,
    passengerName: input.passengerName,
    passengerPhone: input.passengerPhone,
    companyName: input.companyName,
    companyPhone: companyInfo?.phone,
    companyEmail: companyInfo?.email,
    companyAddress: companyInfo?.address,
    companyNif: companyInfo?.nif,
    companyRccm: companyInfo?.rccm,
    companyTva: companyInfo?.tva,
    companyBankAccount: companyInfo?.bankAccount,
    companyLogoUrl: companyInfo?.logoUrl ?? undefined,
    boardingMessage: input.boardingMessage ?? companyInfo?.boardingMessage,
    originCity: input.trip.originCity,
    originStation: input.trip.originStation ?? input.trip.originCity,
    destCity: input.trip.destCity,
    destStation: input.trip.destStation ?? input.trip.destCity,
    departureTime: fmt(input.trip.departureTime, "dd/MM/yyyy HH:mm"),
    arrivalTime: input.trip.arrivalTime ? fmt(input.trip.arrivalTime, "dd/MM/yyyy HH:mm") : "",
    busName: input.trip.busName,
    busPlateNumber: input.trip.busPlateNumber,
    busType: input.trip.busType,
    ticketPrice: input.trip.priceAmount,
    currency: input.trip.currency,
    parcelCount: parcel?.count,
    parcelWeight: parcel?.weight,
    parcelAmount: parcel?.amount,
    totalPrice: input.totalPrice,
    issuedAt: fmt(new Date().toISOString(), "dd/MM/yyyy HH:mm"),
    verifyUrl: buildVerifyUrl(input),
  };
}

export async function downloadTicketReceiptPdf(
  input: TicketReceiptInput,
  format: ReceiptFormat,
): Promise<void> {
  await generateReceiptPDF(buildTicketReceiptPdfData(input), format);
}

export async function downloadTicketReceiptImage(
  node: HTMLElement | null,
  reference: string,
): Promise<Blob | null> {
  if (!node) return null;
  try {
    const dataUrl = await toPng(node, {
      cacheBust: true,
      backgroundColor: "#ffffff",
      pixelRatio: 2,
    });
    const link = document.createElement("a");
    link.download = `receipt-${reference}.png`;
    link.href = dataUrl;
    link.click();

    const response = await fetch(dataUrl);
    return await response.blob();
  } catch {
    toast.error("Impossible de generer l'image du recu");
    return null;
  }
}

export async function createTicketReceiptImageBlob(
  node: HTMLElement | null,
): Promise<Blob | null> {
  if (!node) return null;
  try {
    const dataUrl = await toPng(node, {
      cacheBust: true,
      backgroundColor: "#ffffff",
      pixelRatio: 2,
    });
    const response = await fetch(dataUrl);
    return await response.blob();
  } catch {
    return null;
  }
}

export function buildTicketReceiptShareCaption(input: TicketReceiptInput): string {
  return [
    `Ticket Tibus - ${input.reference}`,
    input.companyName,
    input.passengerName,
    `${input.trip.originCity} -> ${input.trip.destCity}`,
    `Depart: ${fmt(input.trip.departureTime, "dd/MM/yyyy HH:mm")}`,
    `${input.trip.currency} ${input.totalPrice.toLocaleString()}`,
    "",
    `Verification: ${buildVerifyUrl(input)}`,
    "Powered by Tibus",
  ].join("\n");
}

function openWhatsappShareLink(caption: string, phoneNumber?: string): void {
  const digits = phoneNumber?.replace(/\D/g, "") ?? "";
  const url = digits
    ? `https://wa.me/${digits}?text=${encodeURIComponent(caption)}`
    : `https://wa.me/?text=${encodeURIComponent(caption)}`;
  window.open(url, "_blank", "noopener,noreferrer");
}

export async function shareTicketReceiptImageViaWhatsapp(
  node: HTMLElement | null,
  options: {
    reference: string;
    caption?: string;
    phoneNumber?: string;
  },
): Promise<void> {
  if (!node) {
    toast.error("Recu introuvable");
    return;
  }

  const caption = options.caption ?? `Ticket Tibus - ${options.reference}`;
  const blob = await createTicketReceiptImageBlob(node);
  if (!blob) {
    toast.error("Impossible de generer l'image du ticket");
    return;
  }

  const file = new File([blob], `ticket-${options.reference}.png`, {
    type: "image/png",
  });

  if (
    typeof navigator.share === "function" &&
    typeof navigator.canShare === "function" &&
    navigator.canShare({ files: [file] })
  ) {
    try {
      await navigator.share({
        title: `Ticket ${options.reference}`,
        text: caption,
        files: [file],
      });
      return;
    } catch (error) {
      if (error instanceof Error && error.name === "AbortError") return;
    }
  }

  const objectUrl = URL.createObjectURL(blob);
  const link = document.createElement("a");
  link.download = `ticket-${options.reference}.png`;
  link.href = objectUrl;
  link.click();
  URL.revokeObjectURL(objectUrl);

  openWhatsappShareLink(caption, options.phoneNumber);
  toast.success("Image telechargee. Joignez-la dans WhatsApp si besoin.");
}

export async function shareTicketReceiptText(input: TicketReceiptInput): Promise<void> {
  const text = [
    `Ticket Tibus - ${input.reference}`,
    input.companyName,
    input.passengerName,
    `${input.trip.originCity} -> ${input.trip.destCity}`,
    `Depart: ${fmt(input.trip.departureTime, "dd/MM/yyyy HH:mm")}`,
    `${input.trip.currency} ${input.totalPrice.toLocaleString()}`,
    "",
    `Verification: ${buildVerifyUrl(input)}`,
    "Powered by Tibus",
  ].join("\n");

  if (typeof navigator.share === "function") {
    try {
      await navigator.share({ title: `Ticket ${input.reference}`, text });
      return;
    } catch {
      /* cancelled */
    }
  }
  try {
    await navigator.clipboard.writeText(text);
    toast.success("Copie dans le presse-papiers");
    return;
  } catch {
    /* failed */
  }
  window.open(`https://wa.me/?text=${encodeURIComponent(text)}`, "_blank");
}
