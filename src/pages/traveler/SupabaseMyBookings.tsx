import { Link, useParams } from "react-router-dom";
import {
  TicketIcon,
  CalendarIcon,
  ClockIcon,
  ChevronRightIcon,
  BusIcon,
  CheckCircleIcon,
  AlertCircleIcon,
  ArchiveIcon,
  XCircleIcon,
  MegaphoneIcon,
} from "lucide-react";
import { useState } from "react";
import { toast } from "sonner";
import { Badge } from "@/components/ui/badge.tsx";
import { Button } from "@/components/ui/button.tsx";
import { Label } from "@/components/ui/label.tsx";
import { Textarea } from "@/components/ui/textarea.tsx";
import {
  Dialog,
  DialogContent,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog.tsx";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select.tsx";
import { errorMessage } from "@/lib/utils";
import {
  reportTripIncidentSupabase,
  TRIP_INCIDENT_CATEGORIES,
  TRIP_INCIDENT_CATEGORY_LABELS,
} from "@/lib/supabase/trip-incidents.ts";
import { Skeleton } from "@/components/ui/skeleton.tsx";
import { Empty, EmptyHeader, EmptyMedia, EmptyTitle, EmptyDescription, EmptyContent } from "@/components/ui/empty.tsx";
import { format, parseISO } from "date-fns";
import { useSupabaseAuth } from "@/components/providers/supabase-auth";
import { useSupabaseMyBookings } from "@/hooks/use-supabase-bookings";
import type { TravelerBooking } from "@/lib/supabase/bookings";
import {
  Authenticated,
  Unauthenticated,
  AuthLoading,
} from "@/components/auth/AuthBoundary.tsx";
import { SignInButton } from "@/components/ui/signin.tsx";
import { useTranslation } from "react-i18next";

function fmt(iso: string, pattern: string) {
  try { return format(parseISO(iso), pattern); } catch { return iso; }
}

const STATUS_CONFIG: Record<string, { icon: typeof CheckCircleIcon; color: string; bgColor: string; variant: "default" | "secondary" | "destructive" | "outline" }> = {
  confirmed: { icon: CheckCircleIcon, color: "text-green-600 dark:text-green-400", bgColor: "bg-green-500/10", variant: "default" },
  pending_payment: { icon: AlertCircleIcon, color: "text-amber-600 dark:text-amber-400", bgColor: "bg-amber-500/10", variant: "secondary" },
  cancelled: { icon: XCircleIcon, color: "text-destructive", bgColor: "bg-destructive/10", variant: "destructive" },
  collected: { icon: ArchiveIcon, color: "text-muted-foreground", bgColor: "bg-muted", variant: "outline" },
};

function IncidentDialog({
  bookingId,
  onClose,
}: {
  bookingId: string;
  onClose: () => void;
}) {
  const { t } = useTranslation("traveler");
  const [category, setCategory] = useState<string>("retard");
  const [message, setMessage] = useState("");
  const [sending, setSending] = useState(false);

  const submit = async () => {
    if (!message.trim()) {
      toast.error(t("incident.message_required", { defaultValue: "Décrivez l'incident." }));
      return;
    }
    setSending(true);
    try {
      await reportTripIncidentSupabase({ bookingId, category, message });
      toast.success(
        t("incident.sent", {
          defaultValue: "Incident signalé. La compagnie a été notifiée, merci.",
        }),
      );
      onClose();
    } catch (err) {
      toast.error(errorMessage(err, t("incident.error", { defaultValue: "Signalement impossible." })));
    } finally {
      setSending(false);
    }
  };

  return (
    <Dialog open onOpenChange={(open) => !open && !sending && onClose()}>
      <DialogContent className="max-w-sm">
        <DialogHeader>
          <DialogTitle>
            {t("incident.title", { defaultValue: "Signaler un incident" })}
          </DialogTitle>
        </DialogHeader>
        <div className="space-y-4 py-1">
          <div className="space-y-1.5">
            <Label>{t("incident.category", { defaultValue: "Type d'incident" })}</Label>
            <Select value={category} onValueChange={setCategory}>
              <SelectTrigger>
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                {TRIP_INCIDENT_CATEGORIES.map((value) => (
                  <SelectItem key={value} value={value}>
                    {TRIP_INCIDENT_CATEGORY_LABELS[value]}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>
          <div className="space-y-1.5">
            <Label>{t("incident.message", { defaultValue: "Description" })}</Label>
            <Textarea
              rows={4}
              maxLength={1000}
              value={message}
              onChange={(e) => setMessage(e.target.value)}
              placeholder={t("incident.message_placeholder", {
                defaultValue: "Décrivez ce qui s'est passé (lieu, heure, détails)…",
              })}
            />
          </div>
        </div>
        <DialogFooter>
          <Button type="button" variant="secondary" onClick={onClose} disabled={sending}>
            {t("buttons.cancel", { ns: "common" })}
          </Button>
          <Button type="button" onClick={() => void submit()} disabled={sending}>
            {sending
              ? t("incident.sending", { defaultValue: "Envoi…" })
              : t("incident.submit", { defaultValue: "Envoyer le signalement" })}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

function SupabaseMyBookingsInner() {
  const { t } = useTranslation("traveler");
  const { lng } = useParams<{ lng: string }>();
  const { appUserId } = useSupabaseAuth();
  const { bookings } = useSupabaseMyBookings(appUserId);
  const [incidentBookingId, setIncidentBookingId] = useState<string | null>(null);

  if (bookings === undefined) {
    return (
      <div className="space-y-3">
        {Array.from({ length: 3 }).map((_, i) => (
          <Skeleton key={i} className="h-36 w-full rounded-xl" />
        ))}
      </div>
    );
  }

  if (bookings.length === 0) {
    return (
      <Empty>
        <EmptyHeader>
          <EmptyMedia variant="icon"><TicketIcon /></EmptyMedia>
          <EmptyTitle>{t("no_bookings")}</EmptyTitle>
          <EmptyDescription>
            {t("no_bookings_desc")} Seuls les billets payés apparaissent ici — aucun ticket n'est
            émis avant confirmation du paiement.
          </EmptyDescription>
        </EmptyHeader>
        <EmptyContent>
          <Link to={`/${lng}/traveler`}>
            <Button size="sm" className="cursor-pointer">{t("browse_trips")}</Button>
          </Link>
        </EmptyContent>
      </Empty>
    );
  }

  const active = bookings.filter((b) => b.status !== "cancelled" && b.status !== "collected");
  const past = bookings.filter((b) => b.status === "cancelled" || b.status === "collected");

  const BookingCard = ({ b }: { b: TravelerBooking }) => {
    const config = STATUS_CONFIG[b.status] ?? { icon: TicketIcon, color: "text-muted-foreground", bgColor: "bg-muted", variant: "secondary" as const };
    const StatusIcon = config.icon;
    const canViewReceipt = b.paymentStatus === "paid";

    return (
      <div className="rounded-xl border overflow-hidden transition-all hover:shadow-sm">
        {/* Colored status header */}
        <div className={`px-4 py-2 flex items-center gap-2 ${config.bgColor}`}>
          <StatusIcon className={`w-3.5 h-3.5 ${config.color}`} />
          <span className={`text-xs font-semibold ${config.color}`}>
            {t(`status.${b.status}`, { ns: "common", defaultValue: b.status })}
          </span>
          <code className="text-[10px] bg-background/60 backdrop-blur px-1.5 py-0.5 rounded font-mono ml-auto">
            {b.bookingReference}
          </code>
        </div>

        <div className="p-4 space-y-3">
          {/* Route info */}
          <div className="flex items-start justify-between gap-3">
            <div className="flex items-center gap-3 min-w-0">
              <div className="flex flex-col items-center shrink-0">
                <div className="w-2 h-2 rounded-full border-2 border-primary bg-primary/20" />
                <div className="w-px h-5 bg-primary/40" />
                <div className="w-2 h-2 rounded-full border-2 border-primary bg-primary" />
              </div>
              <div className="min-w-0 space-y-1">
                <p className="font-semibold text-sm truncate">{b.originLoc?.city ?? "?"}</p>
                <p className="font-semibold text-sm truncate">{b.destLoc?.city ?? "?"}</p>
              </div>
            </div>
            <div className="text-right shrink-0">
              <p className="text-lg font-black text-primary">
                {b.totalPrice.toLocaleString()}
              </p>
              <p className="text-[10px] text-muted-foreground">{b.currency}</p>
            </div>
          </div>

          {/* Trip meta */}
          <div className="flex items-center gap-3 text-xs text-muted-foreground flex-wrap">
            {b.trip && (
              <>
                <span className="flex items-center gap-1">
                  <CalendarIcon className="w-3 h-3" />
                  {fmt(b.trip.departureTime, "dd MMM yyyy")}
                </span>
                <span className="flex items-center gap-1 font-medium text-foreground">
                  <ClockIcon className="w-3 h-3" />
                  {fmt(b.trip.departureTime, "HH:mm")}
                </span>
              </>
            )}
            {b.company && (
              <span className="flex items-center gap-1">
                <BusIcon className="w-3 h-3" />
                {b.company.name}
              </span>
            )}
            {b.seatNumber && (
              <Badge variant="secondary" className="text-[10px] gap-0.5">
                {t("seat_label", { defaultValue: "Seat", ns: "common" })} #{b.seatNumber}
              </Badge>
            )}
          </div>

          {/* Actions */}
          <div className="flex items-center justify-between gap-2 pt-1 border-t">
            {b.status !== "cancelled" ? (
              <button
                type="button"
                className="text-xs text-muted-foreground hover:text-destructive flex items-center gap-1 cursor-pointer"
                onClick={() => setIncidentBookingId(b._id)}
              >
                <MegaphoneIcon className="w-3.5 h-3.5" />
                {t("incident.report_btn", { defaultValue: "Signaler un incident" })}
              </button>
            ) : (
              <span />
            )}
            {canViewReceipt ? (
              <Link
                to={`/${lng}/booking/${b._id}`}
                className="text-xs text-primary flex items-center gap-0.5 hover:underline font-medium cursor-pointer"
              >
                <TicketIcon className="w-3.5 h-3.5 mr-0.5" />
                {t("view_receipt")} <ChevronRightIcon className="w-3.5 h-3.5" />
              </Link>
            ) : (
              <span className="text-xs text-muted-foreground italic">
                Reçu disponible après paiement
              </span>
            )}
          </div>
        </div>
      </div>
    );
  };

  return (
    <>
      <div className="space-y-5">
        {active.length > 0 && (
          <div className="space-y-3">
            <div className="flex items-center justify-between">
              <h2 className="text-sm font-semibold text-muted-foreground uppercase tracking-wider">{t("active")}</h2>
              <Badge variant="secondary" className="text-[10px]">{active.length}</Badge>
            </div>
            {active.map((b) => <BookingCard key={b._id} b={b} />)}
          </div>
        )}
        {past.length > 0 && (
          <div className="space-y-3">
            <div className="flex items-center justify-between">
              <h2 className="text-sm font-semibold text-muted-foreground uppercase tracking-wider">{t("past")}</h2>
              <Badge variant="secondary" className="text-[10px]">{past.length}</Badge>
            </div>
            {past.map((b) => <BookingCard key={b._id} b={b} />)}
          </div>
        )}
      </div>

      {incidentBookingId ? (
        <IncidentDialog
          bookingId={incidentBookingId}
          onClose={() => setIncidentBookingId(null)}
        />
      ) : null}

    </>
  );
}

export default function SupabaseMyBookings() {
  const { t } = useTranslation("traveler");
  const { lng } = useParams<{ lng: string }>();

  return (
    <div className="max-w-2xl mx-auto px-4 py-6 space-y-5">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-extrabold tracking-tight">{t("my_bookings")}</h1>
          <p className="text-muted-foreground text-sm mt-1">{t("all_bookings")}</p>
        </div>
        <Link to={`/${lng}/traveler/search`}>
          <Button size="sm" variant="secondary" className="cursor-pointer gap-1.5 text-xs">
            <TicketIcon className="w-3.5 h-3.5" />
            {t("browse_trips")}
          </Button>
        </Link>
      </div>

      <AuthLoading>
        <div className="space-y-3">
          {Array.from({ length: 3 }).map((_, i) => (
            <Skeleton key={i} className="h-36 w-full rounded-xl" />
          ))}
        </div>
      </AuthLoading>
      <Authenticated>
        <SupabaseMyBookingsInner />
      </Authenticated>
      <Unauthenticated>
        <div className="rounded-xl border p-8 text-center space-y-4">
          <TicketIcon className="w-10 h-10 mx-auto text-muted-foreground opacity-40" />
          <p className="text-sm text-muted-foreground">{t("auth.sign_in_to_view", { ns: "common" })}</p>
          <SignInButton />
        </div>
      </Unauthenticated>
    </div>
  );
}
