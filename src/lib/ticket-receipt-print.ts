import { format, parseISO } from "date-fns";
import { toast } from "sonner";
import { RECEIPT_POWERED_BY_LINE } from "@/lib/receipt-branding.ts";
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
  /** Option "Payer en gare" */
  isStationBooking?: boolean;
  stationDueAmount?: number; // M — montant billet à régler en gare
};

export type ThermalPaperWidth = "80mm" | "56mm";

type TibusP3Bridge = {
  printReceipt58?: (title: string, payload: string) => void;
  printReceipt80?: (title: string, payload: string) => void;
  shareWhatsAppImage?: (base64: string, phoneNumber?: string) => void;
  shareImage?: (base64: string, mimeType: string, phoneNumber?: string) => void;
};

const receiptBlobCache = new Map<string, Promise<Blob | null>>();

function receiptBlobCacheKey(reference: string): string {
  return reference.trim() || "ticket-receipt";
}

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

  // ─── Mention "Payer en gare" (imprimante thermique) ───
  if (input.isStationBooking) {
    lines.push(
      { text: sep },
      { text: "*** RECU DE RESERVATION ***", align: "center", bold: true },
      { text: "Ceci est un recu de reservation.", align: "center", size: "small" },
      { text: "Le montant du a la compagnie est", align: "center", size: "small" },
      { text: "a regler en gare de depart.", align: "center", size: "small" },
    );
    if (input.stationDueAmount && input.stationDueAmount > 0) {
      lines.push({
        text: `Montant gare: ${input.trip.currency} ${input.stationDueAmount.toLocaleString()}`,
        align: "center",
        bold: true,
      });
    }
  }

  const boarding = input.boardingMessage ?? companyInfo?.boardingMessage;
  if (boarding) {
    lines.push({ text: sep }, { text: `! ${boarding}`, size: "small" });
  }

  lines.push({ text: sep }, { text: RECEIPT_POWERED_BY_LINE, align: "center", size: "small" });
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
    isStationBooking: input.isStationBooking,
    stationDueAmount: input.stationDueAmount,
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
  const blob = await createTicketReceiptImageBlob(node);
  if (!blob) {
    toast.error("Impossible de generer l'image du recu");
    return null;
  }

  const objectUrl = URL.createObjectURL(blob);
  const link = document.createElement("a");
  link.download = `receipt-${reference}.png`;
  link.href = objectUrl;
  link.click();
  URL.revokeObjectURL(objectUrl);
  return blob;
}


async function waitForReceiptImages(node: HTMLElement): Promise<void> {
  const images = node.querySelectorAll("img");
  await Promise.all(
    [...images].map(
      (img) =>
        new Promise<void>((resolve) => {
          if (img.complete) {
            resolve();
            return;
          }
          img.onload = () => resolve();
          img.onerror = () => resolve();
        }),
    ),
  );
}

async function renderReceiptImageBlob(node: HTMLElement): Promise<Blob | null> {
  await waitForReceiptImages(node);
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

export async function createTicketReceiptImageBlob(
  node: HTMLElement | null,
): Promise<Blob | null> {
  if (!node) return null;
  return renderReceiptImageBlob(node);
}

export function warmTicketReceiptImageBlob(
  node: HTMLElement | null,
  reference: string,
): void {
  if (!node || !reference.trim()) return;
  const key = receiptBlobCacheKey(reference);
  if (receiptBlobCache.has(key)) return;
  receiptBlobCache.set(key, createTicketReceiptImageBlob(node));
}

export function scheduleWarmTicketReceiptImageBlob(
  node: HTMLElement | null,
  reference: string,
  maxAttempts = 24,
): void {
  if (!node || !reference.trim()) return;
  let attempts = 0;
  const tryWarm = () => {
    const qrImg = node.querySelector(".receipt-qr");
    if (
      qrImg instanceof HTMLImageElement &&
      qrImg.complete &&
      qrImg.naturalWidth > 0
    ) {
      warmTicketReceiptImageBlob(node, reference);
      return;
    }
    attempts += 1;
    if (attempts < maxAttempts) {
      requestAnimationFrame(tryWarm);
      return;
    }
    warmTicketReceiptImageBlob(node, reference);
  };
  requestAnimationFrame(tryWarm);
}

async function resolveTicketReceiptImageBlob(
  node: HTMLElement | null,
  reference: string,
): Promise<Blob | null> {
  if (!node) return null;
  const key = receiptBlobCacheKey(reference);
  const cached = receiptBlobCache.get(key);
  if (cached) return cached;
  const promise = createTicketReceiptImageBlob(node);
  receiptBlobCache.set(key, promise);
  return promise;
}

async function blobToJpeg(blob: Blob, quality = 0.92): Promise<Blob | null> {
  if (typeof createImageBitmap !== "function") return null;
  try {
    const bitmap = await createImageBitmap(blob);
    const canvas = document.createElement("canvas");
    canvas.width = bitmap.width;
    canvas.height = bitmap.height;
    const ctx = canvas.getContext("2d");
    if (!ctx) return null;
    ctx.fillStyle = "#ffffff";
    ctx.fillRect(0, 0, canvas.width, canvas.height);
    ctx.drawImage(bitmap, 0, 0);
    bitmap.close();
    return await new Promise((resolve) => {
      canvas.toBlob((jpeg) => resolve(jpeg), "image/jpeg", quality);
    });
  } catch {
    return null;
  }
}

async function buildShareableReceiptFiles(
  blob: Blob,
  reference: string,
): Promise<File[]> {
  const safeRef = reference.replace(/[^\w-]+/g, "_");
  const files: File[] = [];
  const jpegBlob = await blobToJpeg(blob);
  if (jpegBlob && jpegBlob.size > 0) {
    files.push(new File([jpegBlob], `ticket-${safeRef}.jpg`, { type: "image/jpeg" }));
  }
  files.push(new File([blob], `ticket-${safeRef}.png`, { type: "image/png" }));
  return files;
}

function blobToBase64(blob: Blob): Promise<string> {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => {
      const result = reader.result;
      if (typeof result !== "string") {
        reject(new Error("base64 conversion failed"));
        return;
      }
      resolve(result.split(",")[1] ?? result);
    };
    reader.onerror = () => reject(reader.error ?? new Error("base64 conversion failed"));
    reader.readAsDataURL(blob);
  });
}

async function shareViaNativeBridge(
  blob: Blob,
  phoneNumber?: string,
): Promise<boolean> {
  const bridge = tibusP3();
  if (!bridge?.shareWhatsAppImage && !bridge?.shareImage) return false;
  try {
    const base64 = await blobToBase64(blob);
    if (bridge.shareWhatsAppImage) {
      bridge.shareWhatsAppImage(base64, phoneNumber?.replace(/\D/g, "") || undefined);
      return true;
    }
    if (bridge.shareImage) {
      bridge.shareImage(base64, "image/png", phoneNumber?.replace(/\D/g, "") || undefined);
      return true;
    }
  } catch {
    return false;
  }
  return false;
}

async function shareFilesWithNativeSheet(files: File[]): Promise<boolean> {
  if (typeof navigator.share !== "function" || files.length === 0) return false;

  for (const file of files) {
    const payload = { files: [file] };
    try {
      if (typeof navigator.canShare === "function" && !navigator.canShare(payload)) {
        continue;
      }
      await navigator.share(payload);
      return true;
    } catch (error) {
      if (error instanceof Error && error.name === "AbortError") return true;
    }
  }

  for (const file of files) {
    try {
      await navigator.share({ files: [file] });
      return true;
    } catch (error) {
      if (error instanceof Error && error.name === "AbortError") return true;
    }
  }

  return false;
}

function isMobileDevice(): boolean {
  if (typeof navigator === "undefined") return false;
  return /Android|iPhone|iPad|iPod/i.test(navigator.userAgent);
}

function isDesktopBrowser(): boolean {
  return !isMobileDevice();
}

function openWhatsappChatForImageShare(phoneNumber?: string): void {
  const digits = phoneNumber?.replace(/\D/g, "") ?? "";
  const url = digits
    ? isDesktopBrowser()
      ? `https://web.whatsapp.com/send?phone=${digits}`
      : `https://wa.me/${digits}`
    : isDesktopBrowser()
      ? "https://web.whatsapp.com/"
      : "https://wa.me/";
  window.open(url, "_blank", "noopener,noreferrer");
}

async function copyReceiptImageToClipboard(blob: Blob): Promise<boolean> {
  if (typeof ClipboardItem === "undefined" || !navigator.clipboard?.write) {
    return false;
  }

  const candidates: Blob[] = [];
  const jpegBlob = await blobToJpeg(blob);
  if (jpegBlob && jpegBlob.size > 0) candidates.push(jpegBlob);
  if (!candidates.some((item) => item.type === blob.type)) {
    candidates.push(blob);
  }

  for (const candidate of candidates) {
    const type = candidate.type || "image/png";
    try {
      await navigator.clipboard.write([
        new ClipboardItem({
          [type]: candidate,
        }),
      ]);
      return true;
    } catch {
      /* try next format */
    }
  }

  return false;
}

async function shareImageViaClipboardAndWhatsapp(
  blob: Blob,
  phoneNumber?: string,
): Promise<boolean> {
  if (!(await copyReceiptImageToClipboard(blob))) {
    return false;
  }

  openWhatsappChatForImageShare(phoneNumber);
  toast.success(
    isDesktopBrowser()
      ? "Image copiee. Collez-la dans WhatsApp Web (Ctrl+V ou Cmd+V)."
      : "Image copiee. Ouvrez WhatsApp et collez l'image dans la conversation.",
    { duration: 9000 },
  );
  return true;
}

function openReceiptImagePreviewForWhatsapp(blob: Blob, phoneNumber?: string): void {
  const objectUrl = URL.createObjectURL(blob);
  window.open(objectUrl, "_blank", "noopener,noreferrer");
  openWhatsappChatForImageShare(phoneNumber);
  window.setTimeout(() => URL.revokeObjectURL(objectUrl), 300_000);
  toast.success(
    isDesktopBrowser()
      ? "WhatsApp Web ouvert. Glissez l'image depuis l'autre onglet ou copiez-la (clic droit), sans telecharger de fichier."
      : "WhatsApp ouvert. Joignez l'image depuis l'onglet du ticket.",
    { duration: 10_000 },
  );
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
    RECEIPT_POWERED_BY_LINE,
  ].join("\n");
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

  const blob = await resolveTicketReceiptImageBlob(node, options.reference);
  if (!blob || blob.size === 0) {
    toast.error("Impossible de generer l'image du ticket");
    return;
  }

  if (await shareViaNativeBridge(blob, options.phoneNumber)) {
    return;
  }

  const files = await buildShareableReceiptFiles(blob, options.reference);
  if (await shareFilesWithNativeSheet(files)) {
    return;
  }

  if (await shareImageViaClipboardAndWhatsapp(blob, options.phoneNumber)) {
    return;
  }

  openReceiptImagePreviewForWhatsapp(blob, options.phoneNumber);
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
    RECEIPT_POWERED_BY_LINE,
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
