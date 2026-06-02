import { useParams } from "react-router-dom";
import { useQuery } from "convex/react";
import { api } from "@/convex/_generated/api.js";
import { useTranslation } from "react-i18next";
import { format, parseISO } from "date-fns";
import {
  CheckCircleIcon,
  XCircleIcon,
  ClockIcon,
  TicketIcon,
  BusIcon,
  MapPinIcon,
  UserIcon,
  AlertTriangleIcon,
} from "lucide-react";
import { Skeleton } from "@/components/ui/skeleton.tsx";
import { Badge } from "@/components/ui/badge.tsx";

function fmt(iso: string, pattern: string) {
  try {
    return format(parseISO(iso), pattern);
  } catch {
    return iso;
  }
}

const STATUS_CONFIG: Record<string, { icon: typeof CheckCircleIcon; color: string; bg: string }> = {
  confirmed: { icon: CheckCircleIcon, color: "text-green-600", bg: "bg-green-500/10" },
  pending_payment: { icon: ClockIcon, color: "text-yellow-600", bg: "bg-yellow-500/10" },
  cancelled: { icon: XCircleIcon, color: "text-red-600", bg: "bg-red-500/10" },
  collected: { icon: CheckCircleIcon, color: "text-blue-600", bg: "bg-blue-500/10" },
};

export default function TicketVerify() {
  const { t } = useTranslation("traveler");
  const { reference } = useParams<{ reference: string }>();

  const ticket = useQuery(
    api.bookings.verifyByReference,
    reference ? { reference } : "skip"
  );

  if (ticket === undefined) {
    return (
      <div className="max-w-md mx-auto px-4 py-12 space-y-4">
        <Skeleton className="h-32 w-full rounded-xl" />
        <Skeleton className="h-48 w-full rounded-xl" />
      </div>
    );
  }

  if (!ticket) {
    return (
      <div className="max-w-md mx-auto px-4 py-16 text-center space-y-4">
        <div className="w-16 h-16 rounded-full bg-red-500/10 flex items-center justify-center mx-auto">
          <AlertTriangleIcon className="w-8 h-8 text-red-500" />
        </div>
        <h1 className="text-xl font-extrabold">
          {t("verify.not_found", { defaultValue: "Ticket introuvable" })}
        </h1>
        <p className="text-muted-foreground text-sm">
          {t("verify.not_found_desc", {
            defaultValue: "Aucun ticket ne correspond à cette référence. Veuillez vérifier le QR code.",
          })}
        </p>
        {reference && (
          <p className="text-xs font-mono bg-muted px-3 py-1.5 rounded-lg inline-block">
            {reference}
          </p>
        )}
      </div>
    );
  }

  const cfg = STATUS_CONFIG[ticket.status] ?? STATUS_CONFIG.pending_payment;
  const StatusIcon = cfg.icon;
  const isPaid = ticket.paymentStatus === "paid";

  const statusLabel = t(`status.${ticket.status}`, {
    ns: "common",
    defaultValue: ticket.status,
  });

  return (
    <div className="max-w-md mx-auto px-4 py-8 space-y-6">
      {/* Status hero */}
      <div className="text-center space-y-3">
        <div className={`w-16 h-16 rounded-full ${cfg.bg} flex items-center justify-center mx-auto`}>
          <StatusIcon className={`w-8 h-8 ${cfg.color}`} />
        </div>
        <div>
          <h1 className="text-xl font-extrabold">
            {t("verify.title", { defaultValue: "Vérification du ticket" })}
          </h1>
          <Badge
            variant="secondary"
            className={`mt-2 ${cfg.bg} ${cfg.color} border-none`}
          >
            {statusLabel}
          </Badge>
        </div>
      </div>

      {/* Ticket card */}
      <div className="rounded-xl border-2 border-primary/20 bg-card shadow-lg overflow-hidden">
        {/* Reference header */}
        <div className="bg-primary px-5 py-3 flex items-center justify-between">
          <span className="text-white/70 text-xs font-medium uppercase tracking-wider">
            {t("verify.reference", { defaultValue: "Référence" })}
          </span>
          <span className="text-white font-extrabold tracking-widest text-lg">
            {ticket.bookingReference}
          </span>
        </div>

        <div className="px-5 py-4 space-y-4">
          {/* Passenger */}
          <div className="flex items-center gap-3">
            <div className="w-9 h-9 rounded-full bg-muted flex items-center justify-center shrink-0">
              <UserIcon className="w-4 h-4 text-muted-foreground" />
            </div>
            <div>
              <p className="text-xs text-muted-foreground">
                {t("verify.passenger", { defaultValue: "Passager" })}
              </p>
              <p className="font-bold">{ticket.passengerName}</p>
              {ticket.passengerPhone && (
                <p className="text-xs text-muted-foreground">{ticket.passengerPhone}</p>
              )}
            </div>
          </div>

          {/* Route */}
          <div className="flex items-center gap-3">
            <div className="w-9 h-9 rounded-full bg-muted flex items-center justify-center shrink-0">
              <MapPinIcon className="w-4 h-4 text-muted-foreground" />
            </div>
            <div className="flex-1">
              <p className="text-xs text-muted-foreground">
                {t("verify.route", { defaultValue: "Trajet" })}
              </p>
              <p className="font-bold">
                {ticket.originLoc?.city ?? ticket.origin?.name ?? "?"}{" "}
                &rarr;{" "}
                {ticket.destLoc?.city ?? ticket.destination?.name ?? "?"}
              </p>
              <p className="text-xs text-muted-foreground">
                {ticket.origin?.name} &rarr; {ticket.destination?.name}
              </p>
            </div>
          </div>

          {/* Time */}
          {ticket.trip && (
            <div className="flex items-center gap-3">
              <div className="w-9 h-9 rounded-full bg-muted flex items-center justify-center shrink-0">
                <ClockIcon className="w-4 h-4 text-muted-foreground" />
              </div>
              <div>
                <p className="text-xs text-muted-foreground">
                  {t("verify.schedule", { defaultValue: "Horaire" })}
                </p>
                <p className="font-bold">
                  {fmt(ticket.trip.departureTime, "dd MMM yyyy, HH:mm")}
                </p>
                <p className="text-xs text-muted-foreground">
                  &rarr; {fmt(ticket.trip.arrivalTime, "HH:mm")}
                </p>
              </div>
            </div>
          )}

          {/* Bus & Company */}
          <div className="flex items-center gap-3">
            <div className="w-9 h-9 rounded-full bg-muted flex items-center justify-center shrink-0">
              <BusIcon className="w-4 h-4 text-muted-foreground" />
            </div>
            <div>
              <p className="text-xs text-muted-foreground">
                {t("verify.company", { defaultValue: "Compagnie" })}
              </p>
              <p className="font-bold">{ticket.company?.name ?? "-"}</p>
              {ticket.bus && (
                <p className="text-xs text-muted-foreground">
                  {ticket.bus.plateNumber} ({ticket.bus.name})
                </p>
              )}
            </div>
          </div>

          {/* Seat */}
          {ticket.seatNumber && (
            <div className="flex items-center gap-3">
              <div className="w-9 h-9 rounded-full bg-primary/10 flex items-center justify-center shrink-0">
                <span className="text-xs font-bold text-primary">#</span>
              </div>
              <div>
                <p className="text-xs text-muted-foreground">
                  {t("verify.seat", { defaultValue: "Siège" })}
                </p>
                <p className="font-bold text-primary">{ticket.seatNumber}</p>
              </div>
            </div>
          )}

          {/* Price & Payment */}
          <div className="flex items-center gap-3">
            <div className="w-9 h-9 rounded-full bg-muted flex items-center justify-center shrink-0">
              <TicketIcon className="w-4 h-4 text-muted-foreground" />
            </div>
            <div className="flex-1">
              <p className="text-xs text-muted-foreground">
                {t("verify.price", { defaultValue: "Prix" })}
              </p>
              <p className="font-bold">
                {ticket.totalPrice.toLocaleString()} {ticket.currency}
              </p>
            </div>
            <Badge variant={isPaid ? "default" : "secondary"}>
              {isPaid
                ? t("verify.paid", { defaultValue: "Payé" })
                : t("verify.unpaid", { defaultValue: "Non payé" })}
            </Badge>
          </div>
        </div>

        {/* Footer */}
        <div className="border-t border-dashed px-5 py-3 text-center">
          <p className="text-xs font-bold text-primary tracking-wider">
            Powered By Tibus
          </p>
        </div>
      </div>
    </div>
  );
}
