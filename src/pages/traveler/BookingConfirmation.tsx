import { useState, useEffect, useRef, useCallback } from "react";
import { useParams, Link } from "react-router-dom";
import { useQuery, useAction } from "convex/react";
import { api } from "@/convex/_generated/api.js";
import type { Id } from "@/convex/_generated/dataModel.d.ts";
import QRCode from "qrcode";
import { toPng } from "html-to-image";
import { shareTicketReceiptImageViaWhatsapp } from "@/lib/ticket-receipt-print.ts";
import { generateReceiptPDF, type ReceiptFormat, type ReceiptData } from "@/lib/receipt-pdf.ts";
import {
  CheckCircleIcon,
  TicketIcon,
  HomeIcon,
  CreditCardIcon,
  DownloadIcon,
  ShareIcon,
  PrinterIcon,
  FileTextIcon,
} from "lucide-react";
import { Button } from "@/components/ui/button.tsx";
import { Skeleton } from "@/components/ui/skeleton.tsx";
import { format, parseISO } from "date-fns";
import { toast } from "sonner";
import { ConvexError } from "convex/values";
import { useTranslation } from "react-i18next";
import PushOptInPrompt from "@/components/notifications/PushOptInPrompt.tsx";
import { usePushOptIn } from "@/hooks/use-push-optin.ts";

function fmt(iso: string, pattern: string) {
  try { return format(parseISO(iso), pattern); } catch { return iso; }
}

// ─── QR Code Component ──────────────────────────────────────────────────────

function TicketQRCode({ bookingRef }: { bookingRef: string }) {
  const [qrDataUrl, setQrDataUrl] = useState<string | null>(null);

  useEffect(() => {
    const verifyUrl = `${window.location.origin}/verify/${bookingRef}`;
    QRCode.toDataURL(verifyUrl, {
      width: 160,
      margin: 1,
      color: { dark: "#000000", light: "#ffffff" },
      errorCorrectionLevel: "M",
    })
      .then(setQrDataUrl)
      .catch(() => {
        QRCode.toDataURL(bookingRef, { width: 160, margin: 1 })
          .then(setQrDataUrl)
          .catch(() => setQrDataUrl(null));
      });
  }, [bookingRef]);

  if (!qrDataUrl) return null;

  return (
    <div className="flex flex-col items-center gap-1">
      <img src={qrDataUrl} alt="QR Code" className="w-24 h-24 receipt-qr" />
      <p className="text-[9px] text-gray-500">Scan pour vérification</p>
    </div>
  );
}

// ─── Share helper ────────────────────────────────────────────────────────────

function buildShareText(booking: BookingData): string {
  const lines = [
    `🎫 Ticket Tibus — ${booking.bookingReference}`,
    `👤 ${booking.passengerName}`,
    `📍 ${booking.origin?.name ?? "?"} → ${booking.destination?.name ?? "?"}`,
  ];
  if (booking.trip) {
    lines.push(`🕐 ${fmt(booking.trip.departureTime, "dd/MM/yyyy HH:mm")}`);
  }
  lines.push(`💰 ${booking.totalPrice.toLocaleString()} ${booking.currency}`);
  if (booking.company?.name) {
    lines.push(`🚌 ${booking.company.name}`);
  }
  lines.push("");
  lines.push(`Vérification: ${window.location.origin}/verify/${booking.bookingReference}`);
  lines.push("Powered by Tibus");
  return lines.join("\n");
}

async function handleShare(booking: BookingData) {
  const text = buildShareText(booking);
  if (typeof navigator.share === "function") {
    try {
      await navigator.share({ title: `Ticket ${booking.bookingReference}`, text });
      return;
    } catch { /* fall through */ }
  }
  openWhatsApp(text);
}

function openWhatsApp(text: string) {
  const encoded = encodeURIComponent(text);
  window.open(`https://wa.me/?text=${encoded}`, "_blank");
}

// ─── Types ──────────────────────────────────────────────────────────────────

type BookingData = {
  _id: Id<"bookings">;
  bookingReference: string;
  passengerName: string;
  passengerPhone?: string;
  seatNumber?: string;
  totalPrice: number;
  currency: string;
  status: string;
  paymentStatus?: string;
  _creationTime: number;
  commissionAmount?: number;
  commissionPaidBy?: string;
  trip?: {
    departureTime: string;
    arrivalTime: string;
    seatsAvailable: number;
    totalSeats: number;
  } | null;
  bus?: { name: string; plateNumber: string; capacity: number; busType: string } | null;
  origin?: { name: string; address: string; latitude?: number; longitude?: number } | null;
  destination?: { name: string; address: string; latitude?: number; longitude?: number } | null;
  originLoc?: { city: string; country: string; latitude?: number; longitude?: number } | null;
  destLoc?: { city: string; country: string; latitude?: number; longitude?: number } | null;
  company?: { name: string } | null;
};

// ─── Thermal Receipt (print-optimized) ───────────────────────────────────────

function ThermalReceipt({ booking }: { booking: BookingData }) {
  const { t } = useTranslation("traveler");
  const isPaid = booking.paymentStatus === "paid";
  const paidAt = booking._creationTime
    ? format(new Date(booking._creationTime), "dd/MM/yyyy HH:mm")
    : "-";

  return (
    <div>
      <div className="receipt-card bg-white text-black rounded-lg border shadow-sm overflow-hidden mx-auto max-w-sm">
        {/* Header */}
        <div className="receipt-header bg-black text-white px-3 py-2 text-center">
          <p className="font-bold text-sm tracking-wide uppercase">
            {t("receipt.title", { defaultValue: "Reçu de Ticket de Bus" })}
          </p>
          <p className="text-[10px] opacity-80">Tibus</p>
        </div>

        <div className="px-3 py-3 space-y-2 text-xs">
          {/* QR Code */}
          <div className="flex justify-center py-1">
            <TicketQRCode bookingRef={booking.bookingReference} />
          </div>

          {/* TICKET section */}
          <div className="receipt-section-title text-[10px] font-bold text-center tracking-widest text-gray-500">
            --- TICKET ---
          </div>
          <div className="space-y-0.5">
            <ReceiptRow label={t("receipt.ticket_no", { defaultValue: "N°" })} value={booking.bookingReference} bold />
            {booking.seatNumber && (
              <ReceiptRow label={t("receipt.seat", { defaultValue: "Siège" })} value={`#${booking.seatNumber}`} bold />
            )}
            <ReceiptRow label={t("receipt.seats", { defaultValue: "Places" })} value="1" />
            <ReceiptRow label={t("receipt.price", { defaultValue: "Prix" })} value={`${booking.totalPrice.toLocaleString()} ${booking.currency}`} />
            {booking.commissionAmount !== undefined && booking.commissionPaidBy === "traveler" && booking.commissionAmount > 0 && (
              <ReceiptRow label={t("receipt.fees", { defaultValue: "Frais" })} value={`${booking.commissionAmount.toLocaleString()} ${booking.currency}`} />
            )}
            <ReceiptRow label={t("receipt.parcels", { defaultValue: "Colis" })} value="0" />
            <ReceiptRow label={t("receipt.weight", { defaultValue: "Poids" })} value="0 Kg" />
            <ReceiptRow label={t("receipt.parcel_amount", { defaultValue: "Montant colis" })} value={`0 ${booking.currency}`} />
            <div className="border-t border-dashed border-black/30 pt-0.5 mt-0.5">
              <ReceiptRow
                label={t("receipt.total_paid", { defaultValue: "Total" })}
                value={`${booking.totalPrice.toLocaleString()} ${booking.currency}`}
                bold
              />
            </div>
            <ReceiptRow
              label={t("receipt.passenger_name", { defaultValue: "Voyageur" })}
              value={booking.passengerName}
              bold
            />
            {booking.passengerPhone && (
              <ReceiptRow label={t("receipt.phone", { defaultValue: "Tél" })} value={booking.passengerPhone} />
            )}
          </div>

          {/* TRAJET section */}
          <div className="receipt-section-title text-[10px] font-bold text-center tracking-widest text-gray-500">
            --- {t("receipt.route_section", { defaultValue: "TRAJET" })} ---
          </div>
          <div className="space-y-0.5">
            <ReceiptRow
              label={t("receipt.departure", { defaultValue: "Départ" })}
              value={`${booking.origin?.name ?? "?"} (${booking.originLoc?.city ?? "?"})`}
              bold
            />
            {booking.trip && (
              <ReceiptRow
                label={t("receipt.departure_time", { defaultValue: "Heure" })}
                value={fmt(booking.trip.departureTime, "dd/MM/yyyy HH:mm")}
              />
            )}
            {(booking.origin?.latitude !== undefined && booking.origin?.longitude !== undefined) && (
              <ReceiptRow
                label="GPS"
                value={`${booking.origin.latitude.toFixed(4)}, ${booking.origin.longitude.toFixed(4)}`}
              />
            )}
            <ReceiptRow
              label={t("receipt.arrival", { defaultValue: "Arrivée" })}
              value={`${booking.destination?.name ?? "?"} (${booking.destLoc?.city ?? "?"})`}
              bold
            />
            {booking.trip && (
              <ReceiptRow
                label={t("receipt.arrival_time", { defaultValue: "Heure" })}
                value={fmt(booking.trip.arrivalTime, "dd/MM/yyyy HH:mm")}
              />
            )}
            {(booking.destination?.latitude !== undefined && booking.destination?.longitude !== undefined) && (
              <ReceiptRow
                label="GPS"
                value={`${booking.destination.latitude.toFixed(4)}, ${booking.destination.longitude.toFixed(4)}`}
              />
            )}
          </div>

          {/* COMPAGNIE section */}
          <div className="receipt-section-title text-[10px] font-bold text-center tracking-widest text-gray-500">
            --- {t("receipt.company_section", { defaultValue: "COMPAGNIE" })} ---
          </div>
          <div className="space-y-0.5">
            <ReceiptRow
              label={t("receipt.company_name", { defaultValue: "Nom" })}
              value={booking.company?.name ?? "-"}
              bold
            />
            {booking.bus && (
              <>
                <ReceiptRow
                  label="Bus"
                  value={`${booking.bus.plateNumber} (${booking.bus.name})`}
                />
                <ReceiptRow
                  label={t("receipt.capacity", { defaultValue: "Places" })}
                  value={String(booking.bus.capacity)}
                />
              </>
            )}
          </div>

          {/* Footer */}
          <div className="receipt-footer border-t border-dashed border-black/30 pt-2 mt-2 text-center space-y-0.5">
            <p className="text-[9px] text-gray-500 italic">
              {isPaid ? `${t("receipt.paid_on", { defaultValue: "Payé le" })}: ${paidAt}` : t("receipt.not_paid", { defaultValue: "Non payé" })}
            </p>
            <p className="text-[10px] font-bold tracking-wider">Powered By Tibus</p>
          </div>
        </div>
      </div>
    </div>
  );
}

function ReceiptRow({ label, value, bold }: { label: string; value: string; bold?: boolean }) {
  return (
    <div className="receipt-row flex justify-between gap-1 text-[11px] leading-tight">
      <span className="text-gray-600 shrink-0">{label}:</span>
      <span className={`text-right break-words min-w-0 ${bold ? "font-bold" : ""}`}>{value}</span>
    </div>
  );
}

// ─── Main Page ────────────────────────────────────────────────────────────────

export default function BookingConfirmation() {
  const { t } = useTranslation("traveler");
  const { bookingId, lng } = useParams<{ bookingId: string; lng: string }>();
  const booking = useQuery(
    api.bookings.getBooking,
    bookingId ? { bookingId: bookingId as Id<"bookings"> } : "skip"
  );
  const initPayment = useAction(api.fedaPayment.initializePayment);
  const [paying, setPaying] = useState(false);
  const receiptRef = useRef<HTMLDivElement>(null);
  const { showPrompt, triggerAfterBooking, dismiss } = usePushOptIn();

  // Trigger push opt-in when booking is confirmed
  useEffect(() => {
    if (booking && booking.status === "confirmed" && booking.paymentStatus === "paid") {
      triggerAfterBooking();
    }
  }, [booking, triggerAfterBooking]);

  const handleDownload = useCallback(async () => {
    const node = receiptRef.current;
    if (!node) return;
    try {
      const dataUrl = await toPng(node, { cacheBust: true, backgroundColor: "#ffffff", pixelRatio: 2 });
      const link = document.createElement("a");
      link.download = `receipt-${booking?.bookingReference ?? "ticket"}.png`;
      link.href = dataUrl;
      link.click();
    } catch {
      toast.error("Could not generate receipt image");
    }
  }, [booking?.bookingReference]);

  const handleWhatsAppShare = useCallback(() => {
    if (!booking) return;
    void shareTicketReceiptImageViaWhatsapp(receiptRef.current, {
      reference: booking.bookingReference,
      caption: buildShareText(booking as BookingData),
      phoneNumber: booking.passengerPhone,
    });
  }, [booking]);

  const downloadCorporatePDF = useCallback((format: ReceiptFormat) => {
    if (!booking) return;
    const verifyUrl = `${window.location.origin}/${lng ?? "fr"}/verify/${booking.bookingReference}`;
    const receiptData: ReceiptData = {
      bookingReference: booking.bookingReference,
      passengerName: booking.passengerName,
      passengerPhone: booking.passengerPhone,
      companyName: booking.company?.name ?? "Transport Company",
      originCity: booking.originLoc?.city ?? "?",
      originStation: booking.origin?.name ?? booking.originLoc?.city ?? "?",
      destCity: booking.destLoc?.city ?? "?",
      destStation: booking.destination?.name ?? booking.destLoc?.city ?? "?",
      departureTime: booking.trip ? fmt(booking.trip.departureTime, "dd/MM/yyyy HH:mm") : "-",
      arrivalTime: booking.trip ? fmt(booking.trip.arrivalTime, "dd/MM/yyyy HH:mm") : "-",
      busName: booking.bus?.name,
      busPlateNumber: booking.bus?.plateNumber,
      busType: booking.bus?.busType,
      ticketPrice: booking.totalPrice,
      currency: booking.currency,
      totalPrice: booking.totalPrice,
      issuedAt: booking._creationTime ? fmt(new Date(booking._creationTime).toISOString(), "dd/MM/yyyy HH:mm") : "-",
      verifyUrl,
    };
    generateReceiptPDF(receiptData, format);
  }, [booking, lng]);

  if (booking === undefined) {
    return (
      <div className="max-w-md mx-auto px-3 py-6 space-y-3">
        <Skeleton className="h-40 w-full rounded-xl" />
        <Skeleton className="h-24 w-full rounded-xl" />
      </div>
    );
  }

  if (!booking) {
    return (
      <div className="max-w-md mx-auto px-3 py-12 text-center text-muted-foreground">
        <TicketIcon className="w-10 h-10 mx-auto mb-3 opacity-30" />
        <p className="font-medium text-sm">{t("booking_not_found")}</p>
        <Link to={`/${lng}/traveler`}>
          <Button variant="ghost" className="mt-3 cursor-pointer text-sm">{t("buttons.go_home", { ns: "common" })}</Button>
        </Link>
      </div>
    );
  }

  const isPaid = booking.paymentStatus === "paid";
  const isPending = booking.status === "pending_payment";
  const isConfirmed = booking.status === "confirmed" && isPaid;

  const handlePay = async () => {
    setPaying(true);
    try {
      const baseUrl = window.location.origin;
      const successUrl = `${baseUrl}/${lng}/payment/verify?bookingId=${booking._id}`;
      const errorUrl = `${baseUrl}/${lng}/payment/verify?status=failed`;
      const { checkoutUrl } = await initPayment({
        bookingId: booking._id,
        successUrl,
        errorUrl,
      });
      window.location.href = checkoutUrl;
    } catch (err) {
      if (err instanceof ConvexError) {
        const { message } = err.data as { message: string };
        toast.error(message);
      } else {
        toast.error(t("errors.generic", { ns: "common" }));
      }
      setPaying(false);
    }
  };

  return (
    <div className="max-w-md mx-auto px-3 py-4 space-y-4">
      {/* Status header */}
      <div className="text-center space-y-1 print-hide">
        <div className={`w-12 h-12 rounded-full ${isPending ? "bg-yellow-500/10" : "bg-green-500/10"} flex items-center justify-center mx-auto`}>
          {isPending ? (
            <CreditCardIcon className="w-6 h-6 text-yellow-500" />
          ) : (
            <CheckCircleIcon className="w-6 h-6 text-green-500" />
          )}
        </div>
        <h1 className="text-base font-extrabold">
          {isConfirmed ? t("booking_confirmed") : isPending ? t("awaiting_payment") : t("booking_details")}
        </h1>
      </div>

      {/* Pay Now banner for pending bookings */}
      {isPending && (
        <div className="rounded-lg border-2 border-yellow-500/30 bg-yellow-500/5 p-3 space-y-2 print-hide">
          <div className="flex items-center gap-2">
            <CreditCardIcon className="w-4 h-4 text-yellow-600 shrink-0" />
            <p className="text-xs font-semibold text-yellow-700 dark:text-yellow-400">
              {t("payment_required")}
            </p>
          </div>
          <Button
            onClick={handlePay}
            disabled={paying}
            className="w-full cursor-pointer"
            size="sm"
          >
            {paying ? t("redirecting") : `${t("pay_now")} ${booking.currency} ${booking.totalPrice.toLocaleString()}`}
          </Button>
        </div>
      )}

      {/* The receipt (captured as image for download, printed via thermal) */}
      <div id="printable-receipt" ref={receiptRef}>
        <ThermalReceipt booking={booking as BookingData} />
      </div>

      {/* Actions: Print + Download + Share */}
      <div className="space-y-2 print-hide">
        {/* Thermal POS Printing */}
        <div className="rounded-lg border p-3 space-y-2">
          <p className="text-[10px] uppercase tracking-wider font-semibold text-muted-foreground flex items-center gap-1.5">
            <PrinterIcon className="w-3.5 h-3.5" /> {t("receipt.thermal_print", { defaultValue: "Impression Thermique" })}
          </p>
          <div className="flex gap-2">
            <Button variant="secondary" size="sm" className="flex-1 cursor-pointer text-xs" onClick={() => {
              document.documentElement.classList.remove("print-56mm");
              window.print();
            }}>
              80mm
            </Button>
            <Button variant="secondary" size="sm" className="flex-1 cursor-pointer text-xs" onClick={() => {
              document.documentElement.classList.add("print-56mm");
              window.print();
              setTimeout(() => document.documentElement.classList.remove("print-56mm"), 1000);
            }}>
              56mm
            </Button>
          </div>
        </div>

        {/* Corporate PDF Download */}
        <div className="rounded-lg border p-3 space-y-2">
          <p className="text-[10px] uppercase tracking-wider font-semibold text-muted-foreground flex items-center gap-1.5">
            <FileTextIcon className="w-3.5 h-3.5" /> {t("receipt.corporate_pdf", { defaultValue: "Recu Corporate (PDF)" })}
          </p>
          <div className="flex gap-2">
            <Button variant="secondary" size="sm" className="flex-1 cursor-pointer text-xs" onClick={() => downloadCorporatePDF("a4")}>
              <DownloadIcon className="w-3.5 h-3.5 mr-1" /> A4
            </Button>
            <Button variant="secondary" size="sm" className="flex-1 cursor-pointer text-xs" onClick={() => downloadCorporatePDF("a5")}>
              <DownloadIcon className="w-3.5 h-3.5 mr-1" /> A5
            </Button>
          </div>
        </div>

        {/* Quick actions */}
        <div className="space-y-2">
          <div className="flex gap-2">
            <Button variant="secondary" size="sm" className="flex-1 cursor-pointer text-xs" onClick={handleDownload}>
              <DownloadIcon className="w-3.5 h-3.5 mr-1.5" /> PNG
            </Button>
            <Button variant="secondary" size="sm" className="flex-1 cursor-pointer text-xs" onClick={() => handleShare(booking as BookingData)}>
              <ShareIcon className="w-3.5 h-3.5 mr-1.5" /> {t("receipt.share", { defaultValue: "Partager" })}
            </Button>
          </div>
          <Button
            size="sm"
            className="w-full cursor-pointer text-xs bg-[#25D366] hover:bg-[#1ebe57] text-white"
            onClick={handleWhatsAppShare}
          >
            {t("receipt.share_whatsapp_image", { defaultValue: "Partager l'image sur WhatsApp" })}
          </Button>
        </div>
      </div>
      <div className="flex gap-2 print-hide">
        <Link to={`/${lng}/traveler/bookings`} className="flex-1">
          <Button variant="secondary" size="sm" className="w-full cursor-pointer text-xs">
            <TicketIcon className="w-3.5 h-3.5 mr-1.5" /> {t("my_bookings")}
          </Button>
        </Link>
        <Link to={`/${lng}/traveler`} className="flex-1">
          <Button size="sm" className="w-full cursor-pointer text-xs">
            <HomeIcon className="w-3.5 h-3.5 mr-1.5" /> {t("nav.home", { ns: "common" })}
          </Button>
        </Link>
      </div>

      {/* Push notification opt-in prompt */}
      <PushOptInPrompt show={showPrompt} onDismiss={dismiss} />
    </div>
  );
}
