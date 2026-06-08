import { format, parseISO } from "date-fns";
import {
  AlertTriangleIcon,
  BusIcon,
  CheckCircleIcon,
  ClockIcon,
  MapPinIcon,
  TicketIcon,
  UserIcon,
  XCircleIcon,
} from "lucide-react";
import { useTranslation } from "react-i18next";
import { Badge } from "@/components/ui/badge.tsx";
import { Button } from "@/components/ui/button.tsx";
import type { VerifiedTicket } from "@/lib/supabase/ticket-verify.ts";

function fmt(iso: string, pattern: string) {
  try {
    return format(parseISO(iso), pattern);
  } catch {
    return iso;
  }
}

type ResultTone = "success" | "warning" | "error";

function resolveTone(ticket: VerifiedTicket): ResultTone {
  if (ticket.result === "on_board") return "error";
  if (ticket.valid && ticket.result === "valid") return "success";
  if (ticket.result === "duplicate") return "warning";
  return "error";
}

function resolveMessage(ticket: VerifiedTicket, fallback: string): string {
  if (ticket.message === "already_on_board") return fallback;
  if (ticket.message === "passenger_boarded") return fallback;
  return ticket.message || fallback;
}

function hasTicketDetails(ticket: VerifiedTicket): boolean {
  return Boolean(
    ticket.bookingReference &&
      (ticket.passengerName ||
        ticket.companyName ||
        ticket.totalPrice > 0 ||
        ticket.trip?.departureTime ||
        ticket.result === "duplicate" ||
        ticket.result === "on_board"),
  );
}

export default function TicketScanResult({
  ticket,
  compact = false,
  onMarkOnBoard,
  markingOnBoard = false,
}: {
  ticket: VerifiedTicket;
  compact?: boolean;
  onMarkOnBoard?: () => void;
  markingOnBoard?: boolean;
}) {
  const { t } = useTranslation("common");
  const tone = resolveTone(ticket);
  const HeroIcon =
    tone === "success" ? CheckCircleIcon : tone === "warning" ? AlertTriangleIcon : XCircleIcon;

  const title =
    ticket.result === "on_board"
      ? t("scanner.already_on_board_title")
      : tone === "success"
        ? t("scanner.valid_title")
        : tone === "warning"
          ? t("scanner.duplicate_title")
          : t("scanner.refused_title");

  const subtitle = resolveMessage(
    ticket,
    ticket.result === "on_board"
      ? t("scanner.already_on_board_message")
      : ticket.message === "passenger_boarded"
        ? t("scanner.passenger_boarded_message")
        : t("scanner.verify_failed"),
  );

  const toneStyles = {
    success: {
      heroColor: "text-green-600",
      heroBg: "bg-green-500/10",
      borderColor: "border-green-500/30",
      headerBg: "bg-green-600",
    },
    warning: {
      heroColor: "text-amber-600",
      heroBg: "bg-amber-500/10",
      borderColor: "border-amber-500/40",
      headerBg: "bg-amber-600",
    },
    error: {
      heroColor: "text-red-600",
      heroBg: "bg-red-500/10",
      borderColor: "border-red-500/30",
      headerBg: "bg-red-600",
    },
  }[tone];

  const showDetails = hasTicketDetails(ticket);
  const canMarkOnBoard =
    Boolean(onMarkOnBoard) &&
    !ticket.onBoardAt &&
    Boolean(ticket.bookingId) &&
    (ticket.result === "valid" || ticket.result === "duplicate");

  return (
    <div className={`space-y-4 ${compact ? "" : "max-w-md mx-auto"}`}>
      <div className="text-center space-y-3">
        <div className={`w-20 h-20 rounded-full ${toneStyles.heroBg} flex items-center justify-center mx-auto`}>
          <HeroIcon className={`w-10 h-10 ${toneStyles.heroColor}`} />
        </div>
        <div>
          <h2 className={`text-xl font-extrabold ${toneStyles.heroColor}`}>{title}</h2>
          <p
            className={`text-sm mt-1 font-medium ${
              tone === "success"
                ? "text-muted-foreground"
                : tone === "warning"
                  ? "text-amber-800"
                  : "text-red-700"
            }`}
          >
            {subtitle}
          </p>
          {ticket.boardedAt && ticket.result === "duplicate" ? (
            <p className="text-xs text-muted-foreground mt-1">
              {t("scanner.first_scan_at", {
                time: fmt(ticket.boardedAt, "dd/MM/yyyy HH:mm"),
              })}
            </p>
          ) : null}
          {ticket.onBoardAt && ticket.result === "on_board" ? (
            <p className="text-xs text-muted-foreground mt-1">
              {t("scanner.on_board_at", {
                time: fmt(ticket.onBoardAt, "dd/MM/yyyy HH:mm"),
              })}
            </p>
          ) : null}
        </div>
      </div>

      {showDetails ? (
        <div className={`rounded-xl border-2 ${toneStyles.borderColor} bg-card shadow-lg overflow-hidden`}>
          <div className={`px-5 py-3 flex items-center justify-between ${toneStyles.headerBg}`}>
            <span className="text-white/80 text-xs font-medium uppercase tracking-wider">
              Référence
            </span>
            <span className="text-white font-extrabold tracking-widest text-lg">
              {ticket.bookingReference}
            </span>
          </div>

          <div className="px-5 py-4 space-y-4">
            <div className="flex items-center gap-3">
              <div className="w-9 h-9 rounded-full bg-muted flex items-center justify-center shrink-0">
                <UserIcon className="w-4 h-4 text-muted-foreground" />
              </div>
              <div>
                <p className="text-xs text-muted-foreground">Passager</p>
                <p className="font-bold">{ticket.passengerName || "—"}</p>
                {ticket.passengerPhone ? (
                  <p className="text-xs text-muted-foreground">{ticket.passengerPhone}</p>
                ) : null}
              </div>
            </div>

            <div className="flex items-center gap-3">
              <div className="w-9 h-9 rounded-full bg-muted flex items-center justify-center shrink-0">
                <MapPinIcon className="w-4 h-4 text-muted-foreground" />
              </div>
              <div>
                <p className="text-xs text-muted-foreground">Trajet</p>
                <p className="font-bold">
                  {ticket.originLoc?.city ?? ticket.origin?.name ?? "?"}{" "}
                  &rarr; {ticket.destLoc?.city ?? ticket.destination?.name ?? "?"}
                </p>
                {ticket.origin?.name && ticket.destination?.name ? (
                  <p className="text-xs text-muted-foreground">
                    {ticket.origin.name} &rarr; {ticket.destination.name}
                  </p>
                ) : null}
              </div>
            </div>

            {ticket.trip?.departureTime ? (
              <div className="flex items-center gap-3">
                <div className="w-9 h-9 rounded-full bg-muted flex items-center justify-center shrink-0">
                  <ClockIcon className="w-4 h-4 text-muted-foreground" />
                </div>
                <div>
                  <p className="text-xs text-muted-foreground">Horaire</p>
                  <p className="font-bold">
                    {fmt(ticket.trip.departureTime, "dd MMM yyyy, HH:mm")}
                  </p>
                  {ticket.trip.arrivalTime ? (
                    <p className="text-xs text-muted-foreground">
                      &rarr; {fmt(ticket.trip.arrivalTime, "HH:mm")}
                    </p>
                  ) : null}
                </div>
              </div>
            ) : null}

            <div className="flex items-center gap-3">
              <div className="w-9 h-9 rounded-full bg-muted flex items-center justify-center shrink-0">
                <BusIcon className="w-4 h-4 text-muted-foreground" />
              </div>
              <div>
                <p className="text-xs text-muted-foreground">Compagnie</p>
                <p className="font-bold">{ticket.companyName ?? "—"}</p>
                {ticket.bus ? (
                  <p className="text-xs text-muted-foreground">
                    {ticket.bus.plateNumber ? `${ticket.bus.plateNumber} · ` : ""}
                    {ticket.bus.name}
                  </p>
                ) : null}
              </div>
            </div>

            {ticket.seatNumber ? (
              <div className="flex items-center gap-3">
                <div className="w-9 h-9 rounded-full bg-primary/10 flex items-center justify-center shrink-0">
                  <span className="text-xs font-bold text-primary">#</span>
                </div>
                <div>
                  <p className="text-xs text-muted-foreground">Siège</p>
                  <p className="font-bold text-primary">{ticket.seatNumber}</p>
                </div>
              </div>
            ) : null}

            <div className="flex items-center gap-3">
              <div className="w-9 h-9 rounded-full bg-muted flex items-center justify-center shrink-0">
                <TicketIcon className="w-4 h-4 text-muted-foreground" />
              </div>
              <div className="flex-1">
                <p className="text-xs text-muted-foreground">Prix</p>
                <p className="font-bold">
                  {ticket.totalPrice.toLocaleString()} {ticket.currency}
                </p>
              </div>
              <Badge variant={ticket.paymentStatus === "paid" ? "default" : "secondary"}>
                {ticket.paymentStatus === "paid" ? "Payé" : "Non payé"}
              </Badge>
            </div>
          </div>
        </div>
      ) : ticket.bookingReference ? (
        <div className="rounded-xl border border-dashed p-4 text-center text-sm text-muted-foreground">
          Référence <strong>{ticket.bookingReference}</strong> — détails indisponibles en base.
        </div>
      ) : null}

      {canMarkOnBoard ? (
        <Button
          className="w-full cursor-pointer"
          size="lg"
          variant="default"
          disabled={markingOnBoard}
          onClick={onMarkOnBoard}
        >
          {markingOnBoard ? t("scanner.marking_on_board") : t("scanner.mark_on_board")}
        </Button>
      ) : null}
    </div>
  );
}
