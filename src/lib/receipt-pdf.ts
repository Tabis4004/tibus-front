/**
 * Corporate Receipt PDF Generator
 * Generates downloadable A4/A5 receipts with company header, traveler info,
 * trip details, and professional styling using jsPDF.
 */
import jsPDF from "jspdf";
import autoTable from "jspdf-autotable";
import QRCode from "qrcode";

export type ReceiptFormat = "a4" | "a5";

export type ReceiptData = {
  bookingReference: string;
  passengerName: string;
  passengerPhone?: string;
  /** Company */
  companyName: string;
  companyPhone?: string;
  companyEmail?: string;
  companyAddress?: string;
  companyNif?: string;
  companyRccm?: string;
  companyTva?: string;
  companyBankAccount?: string;
  companyLogoUrl?: string;
  boardingMessage?: string;
  /** Trip */
  originCity: string;
  originStation: string;
  destCity: string;
  destStation: string;
  departureTime: string;
  arrivalTime: string;
  /** Bus */
  busName?: string;
  busPlateNumber?: string;
  busType?: string;
  /** Pricing */
  ticketPrice: number;
  currency: string;
  parcelCount?: number;
  parcelWeight?: number;
  parcelAmount?: number;
  totalPrice: number;
  /** Meta */
  issuedAt: string;
  verifyUrl: string;
};

const PRIMARY_COLOR: [number, number, number] = [75, 0, 130]; // Deep purple
const GRAY_DARK: [number, number, number] = [50, 50, 50];
const GRAY_LIGHT: [number, number, number] = [120, 120, 120];
const WHITE: [number, number, number] = [255, 255, 255];
const BG_LIGHT: [number, number, number] = [248, 248, 252];

function drawSeparator(doc: jsPDF, y: number, width: number, margin: number) {
  doc.setDrawColor(200, 200, 210);
  doc.setLineWidth(0.3);
  doc.line(margin, y, width - margin, y);
}

export async function generateReceiptPDF(data: ReceiptData, format: ReceiptFormat): Promise<void> {
  const isA5 = format === "a5";
  const pageWidth = isA5 ? 148 : 210;
  const pageHeight = isA5 ? 210 : 297;
  const margin = isA5 ? 12 : 20;
  const contentWidth = pageWidth - margin * 2;

  const doc = new jsPDF({
    orientation: "portrait",
    unit: "mm",
    format: isA5 ? [148, 210] : "a4",
  });

  let y = margin;

  // ─── Header background band ───
  doc.setFillColor(...PRIMARY_COLOR);
  doc.rect(0, 0, pageWidth, isA5 ? 28 : 36, "F");

  // Company logo (if available, loaded as image)
  let logoLoaded = false;
  if (data.companyLogoUrl) {
    try {
      // Fetch logo as blob and convert to data URL for jsPDF compatibility
      const response = await fetch(data.companyLogoUrl);
      const blob = await response.blob();
      const logoDataUrl = await new Promise<string>((resolve, reject) => {
        const reader = new FileReader();
        reader.onload = () => resolve(reader.result as string);
        reader.onerror = () => reject();
        reader.readAsDataURL(blob);
      });
      // Determine image dimensions
      const img = new Image();
      await new Promise<void>((resolve, reject) => {
        img.onload = () => resolve();
        img.onerror = () => reject();
        img.src = logoDataUrl;
      });
      const logoH = isA5 ? 10 : 14;
      const logoW = (img.width / img.height) * logoH;
      doc.addImage(logoDataUrl, "PNG", (pageWidth - logoW) / 2, isA5 ? 2 : 3, logoW, logoH);
      logoLoaded = true;
    } catch {
      // Logo failed to load, skip it
    }
  }

  // Company name in header
  doc.setTextColor(...WHITE);
  doc.setFontSize(isA5 ? 14 : 18);
  doc.setFont("helvetica", "bold");
  const nameY = logoLoaded ? (isA5 ? 16 : 20) : (isA5 ? 12 : 16);
  doc.text(data.companyName.toUpperCase(), pageWidth / 2, nameY, { align: "center" });

  // Subtitle
  doc.setFontSize(isA5 ? 8 : 10);
  doc.setFont("helvetica", "normal");
  doc.text("CORPORATE RECEIPT / RECU DE VOYAGE", pageWidth / 2, nameY + (isA5 ? 5 : 6), { align: "center" });

  // Company contact in header
  const contactParts: string[] = [];
  if (data.companyPhone) contactParts.push(data.companyPhone);
  if (data.companyEmail) contactParts.push(data.companyEmail);
  if (data.companyAddress) contactParts.push(data.companyAddress);
  if (contactParts.length > 0) {
    doc.setFontSize(isA5 ? 7 : 8);
    doc.text(contactParts.join(" | "), pageWidth / 2, nameY + (isA5 ? 9 : 11), { align: "center" });
  }

  y = isA5 ? 34 : 44;

  // ─── Fiscal info below header ───
  const fiscalParts: string[] = [];
  if (data.companyNif) fiscalParts.push(`NIF: ${data.companyNif}`);
  if (data.companyRccm) fiscalParts.push(`RCCM: ${data.companyRccm}`);
  if (data.companyTva) fiscalParts.push(`TVA: ${data.companyTva}`);
  if (data.companyBankAccount) fiscalParts.push(`Compte: ${data.companyBankAccount}`);
  if (fiscalParts.length > 0) {
    doc.setTextColor(...GRAY_LIGHT);
    doc.setFontSize(isA5 ? 7 : 8);
    doc.setFont("helvetica", "normal");
    doc.text(fiscalParts.join("  |  "), pageWidth / 2, y, { align: "center" });
    y += isA5 ? 5 : 6;
  }

  // ─── Booking Reference box ───
  doc.setFillColor(...BG_LIGHT);
  doc.roundedRect(margin, y, contentWidth, isA5 ? 14 : 16, 2, 2, "F");
  doc.setTextColor(...GRAY_LIGHT);
  doc.setFontSize(isA5 ? 7 : 8);
  doc.text("REFERENCE / N° BILLET", margin + 4, y + (isA5 ? 5 : 6));
  doc.setTextColor(...PRIMARY_COLOR);
  doc.setFontSize(isA5 ? 12 : 14);
  doc.setFont("helvetica", "bold");
  doc.text(data.bookingReference, margin + 4, y + (isA5 ? 11 : 13));

  // Date on right
  doc.setTextColor(...GRAY_LIGHT);
  doc.setFontSize(isA5 ? 7 : 8);
  doc.setFont("helvetica", "normal");
  doc.text(`Date: ${data.issuedAt}`, pageWidth - margin - 4, y + (isA5 ? 11 : 13), { align: "right" });

  y += isA5 ? 18 : 22;

  // ─── Passenger section ───
  doc.setTextColor(...GRAY_DARK);
  doc.setFontSize(isA5 ? 8 : 9);
  doc.setFont("helvetica", "bold");
  doc.text("PASSAGER / PASSENGER", margin, y);
  y += isA5 ? 5 : 6;

  doc.setFont("helvetica", "normal");
  doc.setFontSize(isA5 ? 9 : 11);
  doc.setTextColor(...GRAY_DARK);
  doc.text(data.passengerName, margin, y);
  if (data.passengerPhone) {
    doc.setTextColor(...GRAY_LIGHT);
    doc.setFontSize(isA5 ? 8 : 9);
    doc.text(data.passengerPhone, margin, y + (isA5 ? 4 : 5));
    y += isA5 ? 4 : 5;
  }
  y += isA5 ? 7 : 9;

  drawSeparator(doc, y, pageWidth, margin);
  y += isA5 ? 5 : 6;

  // ─── Trip details table ───
  doc.setTextColor(...GRAY_DARK);
  doc.setFontSize(isA5 ? 8 : 9);
  doc.setFont("helvetica", "bold");
  doc.text("DETAILS DU TRAJET / TRIP DETAILS", margin, y);
  y += isA5 ? 3 : 4;

  const tripRows: string[][] = [
    ["Depart / Origin", `${data.originStation} (${data.originCity})`],
    ["Heure Depart / Departure", data.departureTime],
    ["Arrivee / Destination", `${data.destStation} (${data.destCity})`],
    ["Heure Arrivee / Arrival", data.arrivalTime],
  ];
  if (data.busName) {
    tripRows.push(["Bus", `${data.busName} - ${data.busPlateNumber ?? ""} (${data.busType ?? ""})`]);
  }

  autoTable(doc, {
    startY: y,
    body: tripRows,
    theme: "plain",
    styles: {
      fontSize: isA5 ? 8 : 9,
      cellPadding: isA5 ? 1.5 : 2,
      textColor: GRAY_DARK,
    },
    columnStyles: {
      0: { fontStyle: "bold", cellWidth: isA5 ? 38 : 55, textColor: GRAY_LIGHT },
      1: { cellWidth: isA5 ? 60 : 90 },
    },
    margin: { left: margin, right: margin },
    tableWidth: contentWidth,
  });

  y = (doc as unknown as { lastAutoTable: { finalY: number } }).lastAutoTable.finalY + (isA5 ? 4 : 6);

  drawSeparator(doc, y, pageWidth, margin);
  y += isA5 ? 5 : 6;

  // ─── Pricing table ───
  doc.setTextColor(...GRAY_DARK);
  doc.setFontSize(isA5 ? 8 : 9);
  doc.setFont("helvetica", "bold");
  doc.text("TARIFICATION / PRICING", margin, y);
  y += isA5 ? 3 : 4;

  const priceRows: string[][] = [
    ["Billet / Ticket", `${data.currency} ${data.ticketPrice.toLocaleString()}`],
  ];
  if (data.parcelCount && data.parcelCount > 0) {
    priceRows.push(["Colis / Parcels", `${data.parcelCount} (${data.parcelWeight ?? 0} Kg)`]);
  }
  if (data.parcelAmount && data.parcelAmount > 0) {
    priceRows.push(["Montant colis / Parcel fee", `${data.currency} ${data.parcelAmount.toLocaleString()}`]);
  }

  autoTable(doc, {
    startY: y,
    body: priceRows,
    theme: "plain",
    styles: {
      fontSize: isA5 ? 8 : 9,
      cellPadding: isA5 ? 1.5 : 2,
      textColor: GRAY_DARK,
    },
    columnStyles: {
      0: { fontStyle: "bold", cellWidth: isA5 ? 38 : 55, textColor: GRAY_LIGHT },
      1: { cellWidth: isA5 ? 60 : 90 },
    },
    margin: { left: margin, right: margin },
    tableWidth: contentWidth,
  });

  y = (doc as unknown as { lastAutoTable: { finalY: number } }).lastAutoTable.finalY + (isA5 ? 3 : 4);

  // Total row with background
  doc.setFillColor(...BG_LIGHT);
  doc.roundedRect(margin, y, contentWidth, isA5 ? 8 : 10, 1, 1, "F");
  doc.setTextColor(...PRIMARY_COLOR);
  doc.setFontSize(isA5 ? 10 : 12);
  doc.setFont("helvetica", "bold");
  doc.text("TOTAL", margin + 4, y + (isA5 ? 5.5 : 7));
  doc.text(`${data.currency} ${data.totalPrice.toLocaleString()}`, pageWidth - margin - 4, y + (isA5 ? 5.5 : 7), { align: "right" });

  y += isA5 ? 12 : 16;

  // ─── Boarding message ───
  if (data.boardingMessage) {
    doc.setDrawColor(...PRIMARY_COLOR);
    doc.setLineWidth(0.4);
    doc.roundedRect(margin, y, contentWidth, isA5 ? 10 : 12, 1, 1, "S");
    doc.setTextColor(...PRIMARY_COLOR);
    doc.setFontSize(isA5 ? 7 : 8);
    doc.setFont("helvetica", "bold");
    doc.text("IMPORTANT:", margin + 3, y + (isA5 ? 4 : 5));
    doc.setFont("helvetica", "normal");
    doc.text(data.boardingMessage, margin + (isA5 ? 20 : 28), y + (isA5 ? 4 : 5));
    y += isA5 ? 14 : 18;
  }

  // ─── QR Code & Footer ───
  drawSeparator(doc, y, pageWidth, margin);
  y += isA5 ? 4 : 5;

  // Generate QR code as data URL
  try {
    const qrDataUrl = await QRCode.toDataURL(data.verifyUrl, {
      width: 200,
      margin: 1,
      color: { dark: "#000000", light: "#ffffff" },
      errorCorrectionLevel: "M",
    });
    const qrSize = isA5 ? 22 : 28;
    doc.addImage(qrDataUrl, "PNG", (pageWidth - qrSize) / 2, y, qrSize, qrSize);
    y += qrSize + (isA5 ? 2 : 3);
  } catch {
    // QR failed, skip
  }

  doc.setTextColor(...GRAY_LIGHT);
  doc.setFontSize(isA5 ? 7 : 8);
  doc.setFont("helvetica", "normal");
  doc.text(`Verification: ${data.verifyUrl}`, pageWidth / 2, y, { align: "center" });
  y += isA5 ? 4 : 5;
  doc.setFontSize(isA5 ? 7 : 8);
  doc.setFont("helvetica", "bold");
  doc.text("Powered By Tibus", pageWidth / 2, y, { align: "center" });

  // ─── Page border ───
  doc.setDrawColor(200, 200, 210);
  doc.setLineWidth(0.5);
  doc.rect(4, 4, pageWidth - 8, pageHeight - 8);

  // Save
  doc.save(`receipt-${data.bookingReference}-${format.toUpperCase()}.pdf`);
}
