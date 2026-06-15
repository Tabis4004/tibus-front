import { useCallback, useEffect, useRef, useState } from "react";
import { useTranslation } from "react-i18next";
import { useParams } from "react-router-dom";
import { format, parseISO } from "date-fns";
import QRCode from "qrcode";
import {
  CheckCircleIcon,
  DownloadIcon,
  FileTextIcon,
  PlusIcon,
  PrinterIcon,
  ShareIcon,
} from "lucide-react";
import { Button } from "@/components/ui/button.tsx";
import {
  downloadTicketReceiptImage,
  downloadTicketReceiptPdf,
  isPosPrinterAvailable,
  printTicketReceipt,
  shareTicketReceiptText,
  shareTicketReceiptImageViaWhatsapp,
  warmTicketReceiptImageBlob,
  buildTicketReceiptShareCaption,
  type SellerCompanyReceiptInfo,
  type TicketReceiptInput,
  type TicketReceiptParcel,
  type TicketReceiptTrip,
  type ThermalPaperWidth,
} from "@/lib/ticket-receipt-print.ts";
import { buildTicketVerifyUrl } from "@/lib/ticket-verify-url.ts";

function fmt(iso: string, pattern: string) {
  try {
    return format(parseISO(iso), pattern);
  } catch {
    return iso;
  }
}

export default function SellerTicketReceiptPanel({
  input,
  companyInfo,
  onBack,
  onNewSale,
  onDone,
  showSuccessHeader = true,
}: {
  input: TicketReceiptInput;
  companyInfo?: SellerCompanyReceiptInfo;
  onBack?: () => void;
  onNewSale?: () => void;
  onDone?: () => void;
  showSuccessHeader?: boolean;
}) {
  const { t } = useTranslation("seller");
  const { lng } = useParams<{ lng: string }>();
  const receiptRef = useRef<HTMLDivElement>(null);
  const [qrDataUrl, setQrDataUrl] = useState<string | null>(null);

  const mergedInput: TicketReceiptInput = {
    ...input,
    lng: input.lng ?? lng,
    companyInfo: companyInfo ?? input.companyInfo,
    boardingMessage: input.boardingMessage ?? companyInfo?.boardingMessage,
  };

  useEffect(() => {
    const verifyUrl = buildTicketVerifyUrl({
      reference: mergedInput.reference,
      verifyToken: mergedInput.verifyToken,
      lng: mergedInput.lng,
    });
    void QRCode.toDataURL(verifyUrl, {
      width: 180,
      margin: 1,
      color: { dark: "#000000", light: "#ffffff" },
      errorCorrectionLevel: "M",
    })
      .then(setQrDataUrl)
      .catch(() => setQrDataUrl(null));
  }, [mergedInput.reference, mergedInput.verifyToken, mergedInput.lng]);

  useEffect(() => {
    if (!qrDataUrl) return;
    const frame = requestAnimationFrame(() => {
      warmTicketReceiptImageBlob(receiptRef.current, mergedInput.reference);
    });
    return () => cancelAnimationFrame(frame);
  }, [qrDataUrl, mergedInput.reference]);

  const handleThermalPrint = useCallback(
    (paperWidth: ThermalPaperWidth) => {
      printTicketReceipt(mergedInput, paperWidth);
    },
    [mergedInput],
  );

  const handleDownloadPdf = useCallback(
    async (format: "a4" | "a5") => {
      await downloadTicketReceiptPdf(mergedInput, format);
    },
    [mergedInput],
  );

  const handleDownloadImage = useCallback(() => {
    void downloadTicketReceiptImage(receiptRef.current, mergedInput.reference);
  }, [mergedInput.reference]);

  const handleShare = useCallback(() => {
    void shareTicketReceiptText(mergedInput);
  }, [mergedInput]);

  const handleWhatsAppShare = useCallback(() => {
    void shareTicketReceiptImageViaWhatsapp(receiptRef.current, {
      reference: mergedInput.reference,
      caption: buildTicketReceiptShareCaption(mergedInput),
      phoneNumber: mergedInput.passengerPhone,
    });
  }, [mergedInput]);

  const info = mergedInput.companyInfo;
  const parcel = mergedInput.parcel;
  const posNative = isPosPrinterAvailable();

  return (
    <div className="max-w-md mx-auto px-3 py-4 space-y-4">
      {showSuccessHeader && (
        <div className="text-center space-y-1 print-hide">
          <div className="w-12 h-12 rounded-full bg-green-500/10 flex items-center justify-center mx-auto">
            <CheckCircleIcon className="w-6 h-6 text-green-500" />
          </div>
          <h2 className="text-lg font-extrabold">{t("ticket_sold", { defaultValue: "Ticket vendu" })}</h2>
          <p className="text-xs text-muted-foreground">
            {t("hand_reference", { defaultValue: "Remettez la reference au voyageur" })}
          </p>
        </div>
      )}

      <div
        id="printable-receipt"
        ref={receiptRef}
        className="bg-white text-black py-3 rounded-lg border shadow-sm text-center space-y-2"
      >
        <div className="px-3 pb-2 border-b border-dashed border-black/30 space-y-1">
          {info?.logoUrl && (
            <img src={info.logoUrl} alt="Logo" className="h-10 mx-auto object-contain" />
          )}
          <div className="font-bold text-sm">{mergedInput.companyName}</div>
          {(info?.address || info?.phone || info?.email) && (
            <div className="text-[9px] text-gray-500 leading-tight">
              {info.address && <span>{info.address}</span>}
              {info.phone && <span> | {info.phone}</span>}
              {info.email && <span> | {info.email}</span>}
            </div>
          )}
          {(info?.nif || info?.rccm || info?.tva) && (
            <div className="text-[9px] text-gray-500 leading-tight">
              {info.nif && <span>NIF: {info.nif}</span>}
              {info.rccm && <span>{info.nif ? " | " : ""}RCCM: {info.rccm}</span>}
              {info.tva && <span>{info.nif || info.rccm ? " | " : ""}TVA: {info.tva}</span>}
            </div>
          )}
          {info?.bankAccount && (
            <div className="text-[9px] text-gray-500">Compte: {info.bankAccount}</div>
          )}
        </div>

        <div className="text-[10px] uppercase tracking-widest text-gray-500">
          {t("booking_reference", { defaultValue: "Reference" })}
        </div>
        <p className="text-2xl font-extrabold tracking-widest" style={{ color: "#5b21b6" }}>
          {mergedInput.reference}
        </p>

        {qrDataUrl && (
          <div className="flex flex-col items-center gap-1 pt-1">
            <img src={qrDataUrl} alt="QR" className="w-24 h-24 rounded" />
            <p className="text-[9px] text-gray-500">Scan pour verification</p>
          </div>
        )}

        <div className="space-y-0.5 text-xs text-left px-3 pt-2">
          <div className="flex justify-between gap-1">
            <span className="text-gray-600">{t("passenger_name", { ns: "traveler" })}:</span>
            <span className="font-bold text-right">{mergedInput.passengerName}</span>
          </div>
          {mergedInput.passengerPhone && (
            <div className="flex justify-between gap-1">
              <span className="text-gray-600">{t("phone_optional", { ns: "traveler" })}:</span>
              <span className="text-right">{mergedInput.passengerPhone}</span>
            </div>
          )}
          {mergedInput.seatNumber && (
            <div className="flex justify-between gap-1">
              <span className="text-gray-600">{t("seat_label", { defaultValue: "Siege", ns: "common" })}:</span>
              <span className="font-bold text-right">#{mergedInput.seatNumber}</span>
            </div>
          )}
          <div className="flex justify-between gap-1">
            <span className="text-gray-600">{t("route", { defaultValue: "Trajet" })}:</span>
            <span className="font-bold text-right">
              {mergedInput.trip.originCity} → {mergedInput.trip.destCity}
            </span>
          </div>
          <div className="flex justify-between gap-1">
            <span className="text-gray-600">{t("departure_label", { defaultValue: "Depart" })}:</span>
            <span className="font-bold text-right">
              {fmt(mergedInput.trip.departureTime, "dd/MM/yyyy HH:mm")}
            </span>
          </div>
          {(mergedInput.trip.busName || mergedInput.trip.busPlateNumber) && (
            <div className="flex justify-between gap-1">
              <span className="text-gray-600">Bus:</span>
              <span className="text-right">
                {[mergedInput.trip.busName, mergedInput.trip.busPlateNumber].filter(Boolean).join(" · ")}
              </span>
            </div>
          )}
          {parcel && parcel.count > 0 && (
            <>
              <div className="border-t border-dashed border-black/20 pt-0.5 mt-0.5" />
              <div className="flex justify-between gap-1">
                <span className="text-gray-600">{t("parcels", { defaultValue: "Colis" })}:</span>
                <span className="text-right">{parcel.count}</span>
              </div>
              {parcel.weight > 0 && (
                <div className="flex justify-between gap-1">
                  <span className="text-gray-600">{t("parcel_weight", { defaultValue: "Poids" })}:</span>
                  <span className="text-right">{parcel.weight} Kg</span>
                </div>
              )}
              {parcel.amount > 0 && (
                <div className="flex justify-between gap-1">
                  <span className="text-gray-600">{t("parcel_price", { defaultValue: "Montant colis" })}:</span>
                  <span className="text-right">
                    {mergedInput.trip.currency} {parcel.amount.toLocaleString()}
                  </span>
                </div>
              )}
            </>
          )}
          <div className="flex justify-between gap-1 border-t border-dashed border-black/20 pt-0.5 mt-0.5">
            <span className="text-gray-600 font-bold">Total:</span>
            <span className="font-bold text-right">
              {mergedInput.trip.currency} {mergedInput.totalPrice.toLocaleString()}
            </span>
          </div>
        </div>

        {mergedInput.boardingMessage && (
          <div className="mx-3 mt-2 px-2 py-1.5 border border-dashed border-black/30 rounded text-[10px] text-left leading-tight">
            <span className="font-bold">!</span> {mergedInput.boardingMessage}
          </div>
        )}

        <div className="border-t border-dashed border-black/30 pt-2 mt-2 text-[9px] font-bold tracking-wider">
          Powered By Tibus
        </div>
      </div>

      <div className="space-y-2 print-hide">
        <div className="rounded-lg border p-3 space-y-2">
          <p className="text-[10px] uppercase tracking-wider font-semibold text-muted-foreground flex items-center gap-1.5">
            <PrinterIcon className="w-3.5 h-3.5" />
            {t("thermal_print", { defaultValue: "Impression Thermique (POS)" })}
          </p>
          <div className="flex gap-2">
            <Button
              variant="secondary"
              size="sm"
              className="flex-1 cursor-pointer text-xs"
              onClick={() => handleThermalPrint("80mm")}
            >
              <PrinterIcon className="w-3.5 h-3.5 mr-1" />
              {posNative ? "POS" : t("print", { defaultValue: "Imprimer" })}
            </Button>
            <Button variant="secondary" size="sm" className="flex-1 cursor-pointer text-xs" onClick={() => handleThermalPrint("80mm")}>
              80mm
            </Button>
            <Button variant="secondary" size="sm" className="flex-1 cursor-pointer text-xs" onClick={() => handleThermalPrint("56mm")}>
              56mm
            </Button>
          </div>
        </div>

        <div className="rounded-lg border p-3 space-y-2">
          <p className="text-[10px] uppercase tracking-wider font-semibold text-muted-foreground flex items-center gap-1.5">
            <FileTextIcon className="w-3.5 h-3.5" />
            {t("corporate_receipt", { defaultValue: "Recu Corporate (PDF)" })}
          </p>
          <div className="flex gap-2">
            <Button variant="secondary" size="sm" className="flex-1 cursor-pointer text-xs" onClick={() => void handleDownloadPdf("a4")}>
              <DownloadIcon className="w-3.5 h-3.5 mr-1" /> A4
            </Button>
            <Button variant="secondary" size="sm" className="flex-1 cursor-pointer text-xs" onClick={() => void handleDownloadPdf("a5")}>
              <DownloadIcon className="w-3.5 h-3.5 mr-1" /> A5
            </Button>
          </div>
        </div>

        <div className="space-y-2">
          <div className="flex gap-2">
            <Button variant="secondary" size="sm" className="flex-1 cursor-pointer text-xs" onClick={handleDownloadImage}>
              <DownloadIcon className="w-3.5 h-3.5 mr-1.5" />
              PNG
            </Button>
            <Button variant="secondary" size="sm" className="flex-1 cursor-pointer text-xs" onClick={handleShare}>
              <ShareIcon className="w-3.5 h-3.5 mr-1.5" />
              {t("share", { defaultValue: "Partager" })}
            </Button>
          </div>
          <Button
            size="sm"
            className="w-full cursor-pointer text-xs bg-[#25D366] hover:bg-[#1ebe57] text-white"
            onClick={handleWhatsAppShare}
          >
            {t("share_whatsapp_image", { defaultValue: "Partager l'image sur WhatsApp" })}
          </Button>
        </div>
      </div>

      <div className="space-y-2 print-hide">
        {onNewSale && (
          <Button onClick={onNewSale} className="w-full cursor-pointer">
            <PlusIcon className="w-4 h-4 mr-1.5" /> {t("sell_ticket", { defaultValue: "Vendre un ticket" })}
          </Button>
        )}
        {onBack && (
          <Button variant="secondary" onClick={onBack} className="w-full cursor-pointer">
            {t("back_to_dashboard", { defaultValue: "Retour" })}
          </Button>
        )}
        {onDone && (
          <Button variant="ghost" onClick={onDone} className="w-full cursor-pointer text-xs">
            {t("done", { ns: "common", defaultValue: "Termine" })}
          </Button>
        )}
      </div>
    </div>
  );
}

export type SellerConvexCompanyInfo = {
  name: string;
  phone?: string;
  email?: string;
  address?: string;
  nif?: string;
  rccm?: string;
  tva?: string;
  bankAccount?: string;
  logoUrl?: string | null;
};

export function sellerCompanyInfoFromConvex(
  companyInfo?: SellerConvexCompanyInfo,
): SellerCompanyReceiptInfo | undefined {
  if (!companyInfo) return undefined;
  return {
    name: companyInfo.name,
    logoUrl: companyInfo.logoUrl,
    phone: companyInfo.phone,
    email: companyInfo.email,
    address: companyInfo.address,
    nif: companyInfo.nif,
    rccm: companyInfo.rccm,
    tva: companyInfo.tva,
    bankAccount: companyInfo.bankAccount,
  };
}

export function sellerSaleToReceiptInput(input: {
  reference: string;
  passengerName: string;
  passengerPhone?: string;
  seatNumber?: string | null;
  totalPrice: number;
  companyName: string;
  boardingMessage?: string;
  companyInfo?: SellerCompanyReceiptInfo;
  parcel?: TicketReceiptParcel | null;
  trip: TicketReceiptTrip;
  lng?: string;
}): TicketReceiptInput {
  return {
    reference: input.reference,
    passengerName: input.passengerName,
    passengerPhone: input.passengerPhone,
    seatNumber: input.seatNumber ?? null,
    totalPrice: input.totalPrice,
    companyName: input.companyName,
    boardingMessage: input.boardingMessage,
    companyInfo: input.companyInfo,
    parcel: input.parcel,
    trip: input.trip,
    lng: input.lng,
  };
}

export function convexTripToReceiptTrip(trip: {
  originLoc?: { city: string } | null;
  destLoc?: { city: string } | null;
  origin?: { name: string } | null;
  destination?: { name: string } | null;
  departureTime: string;
  arrivalTime?: string;
  priceAmount: number;
  currency: string;
  bus?: { name: string; plateNumber?: string; busType?: string } | null;
}): TicketReceiptTrip {
  return {
    originCity: trip.originLoc?.city ?? "?",
    originStation: trip.origin?.name ?? trip.originLoc?.city ?? "?",
    destCity: trip.destLoc?.city ?? "?",
    destStation: trip.destination?.name ?? trip.destLoc?.city ?? "?",
    departureTime: trip.departureTime,
    arrivalTime: trip.arrivalTime,
    priceAmount: trip.priceAmount,
    currency: trip.currency,
    busName: trip.bus?.name,
    busPlateNumber: trip.bus?.plateNumber,
    busType: trip.bus?.busType,
  };
}

export function counterTicketToReceiptInput(
  ticket: {
    reference: string;
    verifyToken?: string | null;
    totalPrice: number;
    currency: string;
    passengerName: string;
    passengerPhone?: string;
    seatNumber?: string;
    parcelCount: number;
    parcelWeight: number;
    parcelAmount: number;
  },
  trip: {
    priceAmount: number;
    currency: string;
    departureTime: string;
    arrivalTime?: string;
    originLoc?: { city: string } | null;
    destLoc?: { city: string } | null;
    origin?: { name: string } | null;
    destination?: { name: string } | null;
    company?: { name: string } | null;
    bus?: { name: string; plateNumber?: string; busType?: string } | null;
  },
  companyName: string,
): TicketReceiptInput {
  const parcel =
    ticket.parcelCount > 0 || ticket.parcelWeight > 0 || ticket.parcelAmount > 0
      ? {
          count: ticket.parcelCount,
          weight: ticket.parcelWeight,
          amount: ticket.parcelAmount,
        }
      : null;

  return {
    reference: ticket.reference,
    verifyToken: ticket.verifyToken,
    passengerName: ticket.passengerName,
    passengerPhone: ticket.passengerPhone,
    seatNumber: ticket.seatNumber ?? null,
    totalPrice: ticket.totalPrice,
    companyName: companyName || trip.company?.name || "Tibus",
    parcel,
    trip: {
      originCity: trip.originLoc?.city ?? "?",
      originStation: trip.origin?.name ?? trip.originLoc?.city ?? "?",
      destCity: trip.destLoc?.city ?? "?",
      destStation: trip.destination?.name ?? trip.destLoc?.city ?? "?",
      departureTime: trip.departureTime,
      arrivalTime: trip.arrivalTime,
      priceAmount: trip.priceAmount,
      currency: trip.currency || ticket.currency,
      busName: trip.bus?.name,
      busPlateNumber: trip.bus?.plateNumber,
      busType: trip.bus?.busType,
    },
  };
}
