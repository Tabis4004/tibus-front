import { useState } from "react";
import { useParams, useNavigate, Link } from "react-router-dom";
import { useQuery, useMutation, useAction, useConvex } from "convex/react";
import { api } from "@/convex/_generated/api.js";
import type { Id } from "@/convex/_generated/dataModel.d.ts";
import {
  ArrowLeftIcon,
  BusIcon,
  MapPinIcon,
  ClockIcon,
  CalendarIcon,
  UsersIcon,
  BuildingIcon,
  CheckCircleIcon,
  CreditCardIcon,
  RouteIcon,
  ShieldCheckIcon,
  ArrowRightIcon,
  TagIcon,
} from "lucide-react";
import { Button } from "@/components/ui/button.tsx";
import { Input } from "@/components/ui/input.tsx";
import { Label } from "@/components/ui/label.tsx";
import { Skeleton } from "@/components/ui/skeleton.tsx";
import { Badge } from "@/components/ui/badge.tsx";
import { Separator } from "@/components/ui/separator.tsx";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogDescription,
  DialogFooter,
} from "@/components/ui/dialog.tsx";
import { toast } from "sonner";
import { ConvexError } from "convex/values";
import { format, parseISO } from "date-fns";
import { Authenticated, Unauthenticated } from "convex/react";
import { SignInButton } from "@/components/ui/signin.tsx";
import { useTranslation } from "react-i18next";
import SeatPicker from "@/components/seat-picker.tsx";

function fmt(iso: string, pattern: string) {
  try { return format(parseISO(iso), pattern); } catch { return iso; }
}

export default function TripDetail() {
  const { t } = useTranslation("traveler");
  const { tripId, lng } = useParams<{ tripId: string; lng: string }>();
  const navigate = useNavigate();
  const trip = useQuery(
    api.bookings.getTripDetails,
    tripId ? { tripId: tripId as Id<"trips"> } : "skip"
  );

  const [dialogOpen, setDialogOpen] = useState(false);
  const [passengerName, setPassengerName] = useState("");
  const [passengerPhone, setPassengerPhone] = useState("");
  const [selectedSeat, setSelectedSeat] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);
  const [promoCode, setPromoCode] = useState("");
  const [promoResult, setPromoResult] = useState<{ valid: boolean; promoId?: string; discountAmount?: number; code?: string; error?: string } | null>(null);
  const [validatingPromo, setValidatingPromo] = useState(false);
  const createBooking = useMutation(api.bookings.createBooking);
  const initPayment = useAction(api.fedaPayment.initializePayment);
  const convex = useConvex();

  // Validate promo code on demand
  const handleValidatePromo = async () => {
    if (!promoCode.trim() || !tripId) return;
    setValidatingPromo(true);
    try {
      const result = await convex.query(api.promoCodes.validatePromoCode, {
        code: promoCode.trim(),
        tripId: tripId as Id<"trips">,
      });
      setPromoResult(result as typeof promoResult);
      if (!result.valid) {
        toast.error(result.error ?? "Code invalide");
      }
    } catch {
      setPromoResult(null);
      toast.error(t("errors.generic", { ns: "common" }));
    } finally {
      setValidatingPromo(false);
    }
  };

  // Fetch occupied seats for this trip
  const occupiedSeats = useQuery(
    api.bookings.getOccupiedSeats,
    tripId ? { tripId: tripId as Id<"trips"> } : "skip"
  );

  if (trip === undefined) {
    return (
      <div className="max-w-3xl mx-auto px-4 py-8 space-y-4">
        <Skeleton className="h-8 w-40" />
        <Skeleton className="h-52 w-full rounded-2xl" />
        <div className="grid md:grid-cols-2 gap-4">
          <Skeleton className="h-32 w-full rounded-xl" />
          <Skeleton className="h-32 w-full rounded-xl" />
        </div>
      </div>
    );
  }

  if (!trip) {
    return (
      <div className="max-w-2xl mx-auto px-4 py-16 text-center text-muted-foreground">
        <BusIcon className="w-12 h-12 mx-auto mb-4 opacity-30" />
        <p className="font-medium">{t("trip_not_found")}</p>
        <Button variant="ghost" className="mt-4 cursor-pointer" onClick={() => navigate(-1)}>
          <ArrowLeftIcon className="w-4 h-4 mr-2" /> {t("buttons.go_back", { ns: "common" })}
        </Button>
      </div>
    );
  }

  const handleBook = async () => {
    if (!passengerName.trim()) {
      toast.error(t("passenger_name"));
      return;
    }
    setLoading(true);
    try {
      const bookingId = await createBooking({
        tripId: trip._id,
        passengerName: passengerName.trim(),
        passengerPhone: passengerPhone.trim() || undefined,
        seatNumber: selectedSeat || undefined,
        promoCodeId: promoResult?.valid && promoResult.promoId
          ? (promoResult.promoId as Id<"promoCodes">)
          : undefined,
      });

      const baseUrl = window.location.origin;
      const successUrl = `${baseUrl}/${lng}/payment/verify?bookingId=${bookingId}`;
      const errorUrl = `${baseUrl}/${lng}/payment/verify?status=failed`;
      const { checkoutUrl } = await initPayment({
        bookingId,
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
      setLoading(false);
    }
  };

  const noSeats = trip.seatsAvailable <= 0;
  const durationMin = trip.route?.estimatedDurationMinutes;
  const durationStr = durationMin
    ? `${Math.floor(durationMin / 60)}h ${durationMin % 60}m`
    : null;

  return (
    <div className="max-w-3xl mx-auto px-4 py-6 space-y-6">
      {/* Back */}
      <button
        onClick={() => navigate(-1)}
        className="flex items-center gap-1.5 text-sm text-muted-foreground hover:text-foreground transition-colors cursor-pointer"
      >
        <ArrowLeftIcon className="w-4 h-4" /> {t("back")}
      </button>

      {/* Route hero card */}
      <div className="rounded-2xl bg-gradient-to-br from-primary/15 via-primary/5 to-transparent border p-6 space-y-4">
        <div className="flex items-center justify-between flex-wrap gap-4">
          {/* Route */}
          <div className="flex items-center gap-4">
            <div className="flex flex-col items-center">
              <div className="w-3.5 h-3.5 rounded-full border-2 border-primary bg-primary/20" />
              <div className="w-0.5 h-8 bg-gradient-to-b from-primary/60 to-primary/30 my-0.5" />
              <div className="w-3.5 h-3.5 rounded-full border-2 border-primary bg-primary" />
            </div>
            <div className="space-y-3">
              <div>
                <p className="text-xl font-black tracking-tight">{trip.originLoc?.city ?? "?"}</p>
                <p className="text-xs text-muted-foreground">{trip.origin?.name}</p>
              </div>
              <div>
                <p className="text-xl font-black tracking-tight">{trip.destLoc?.city ?? "?"}</p>
                <p className="text-xs text-muted-foreground">{trip.destination?.name}</p>
              </div>
            </div>
          </div>

          {/* Time + Date */}
          <div className="text-right space-y-1">
            <p className="text-lg font-bold">
              {fmt(trip.departureTime, "HH:mm")}
              <span className="text-muted-foreground mx-2">→</span>
              {fmt(trip.arrivalTime, "HH:mm")}
            </p>
            <p className="text-sm text-muted-foreground">
              {fmt(trip.departureTime, "EEEE, dd MMMM yyyy")}
            </p>
            {durationStr && (
              <Badge variant="secondary" className="text-[11px] gap-1">
                <RouteIcon className="w-3 h-3" /> {durationStr}
              </Badge>
            )}
          </div>
        </div>
      </div>

      {/* Details grid */}
      <div className="grid md:grid-cols-2 gap-4">
        {/* Trip details card */}
        <div className="rounded-xl border p-4 space-y-3">
          <h3 className="text-xs font-bold uppercase tracking-wider text-muted-foreground">
            {t("labels.trip_details", { ns: "common", defaultValue: "Trip Details" })}
          </h3>
          <div className="space-y-2.5">
            <div className="flex items-center gap-3">
              <div className="w-8 h-8 rounded-lg bg-muted flex items-center justify-center shrink-0">
                <BuildingIcon className="w-4 h-4 text-muted-foreground" />
              </div>
              <div className="flex-1 min-w-0">
                <p className="text-[11px] text-muted-foreground">{t("labels.company", { ns: "common" })}</p>
                <p className="text-sm font-semibold truncate">{trip.company?.name}</p>
              </div>
            </div>
            <div className="flex items-center gap-3">
              <div className="w-8 h-8 rounded-lg bg-muted flex items-center justify-center shrink-0">
                <BusIcon className="w-4 h-4 text-muted-foreground" />
              </div>
              <div className="flex-1 min-w-0">
                <p className="text-[11px] text-muted-foreground">{t("labels.bus", { ns: "common" })}</p>
                <p className="text-sm font-semibold truncate">{trip.bus?.name}</p>
                <p className="text-[11px] text-muted-foreground capitalize">{trip.bus?.busType} · {trip.bus?.plateNumber}</p>
              </div>
            </div>
            <div className="flex items-center gap-3">
              <div className="w-8 h-8 rounded-lg bg-muted flex items-center justify-center shrink-0">
                <UsersIcon className="w-4 h-4 text-muted-foreground" />
              </div>
              <div className="flex-1 min-w-0">
                <p className="text-[11px] text-muted-foreground">{t("labels.available_seats", { ns: "common" })}</p>
                <Badge
                  variant={noSeats ? "destructive" : "secondary"}
                  className="mt-0.5"
                >
                  {noSeats ? t("status.full", { ns: "common" }) : `${trip.seatsAvailable} / ${trip.totalSeats}`}
                </Badge>
              </div>
            </div>
          </div>
        </div>

        {/* Amenities + Info card */}
        <div className="rounded-xl border p-4 space-y-3">
          <h3 className="text-xs font-bold uppercase tracking-wider text-muted-foreground">
            {t("labels.amenities", { ns: "common", defaultValue: "Amenities & Info" })}
          </h3>
          {trip.bus?.amenities && trip.bus.amenities.length > 0 ? (
            <div className="flex flex-wrap gap-1.5">
              {trip.bus.amenities.map((a) => (
                <Badge key={a} variant="secondary" className="text-[11px] gap-1">
                  <CheckCircleIcon className="w-3 h-3 text-primary" />
                  {a}
                </Badge>
              ))}
            </div>
          ) : (
            <p className="text-xs text-muted-foreground italic">
              {t("no_amenities", { defaultValue: "Standard bus without listed amenities" })}
            </p>
          )}

          <Separator />

          <div className="space-y-2">
            <div className="flex items-center gap-2 text-xs">
              <MapPinIcon className="w-3.5 h-3.5 text-muted-foreground" />
              <span className="text-muted-foreground">{t("labels.departure_station", { ns: "common", defaultValue: "Departure" })}:</span>
              <span className="font-medium">{trip.origin?.name}</span>
            </div>
            <div className="flex items-center gap-2 text-xs">
              <MapPinIcon className="w-3.5 h-3.5 text-primary" />
              <span className="text-muted-foreground">{t("labels.arrival_station", { ns: "common", defaultValue: "Arrival" })}:</span>
              <span className="font-medium">{trip.destination?.name}</span>
            </div>
          </div>

          <Separator />

          <div className="flex items-center gap-2 text-xs text-muted-foreground">
            <ShieldCheckIcon className="w-3.5 h-3.5 text-green-600 dark:text-green-400" />
            <span>{t("secure_booking", { defaultValue: "Secure payment via GeniusPay" })}</span>
          </div>
        </div>
      </div>

      {/* Sticky price & book bar */}
      <div className="rounded-xl border p-4 flex items-center justify-between bg-muted/20 sticky bottom-4 z-20 shadow-sm">
        <div>
          <p className="text-[11px] text-muted-foreground">{t("labels.price_per_seat", { ns: "common" })}</p>
          <p className="text-2xl font-black text-primary tracking-tight">
            {trip.currency} {trip.priceAmount.toLocaleString()}
          </p>
        </div>
        <Authenticated>
          <Button
            size="lg"
            disabled={noSeats}
            className="cursor-pointer gap-2"
            onClick={() => setDialogOpen(true)}
          >
            {noSeats ? t("sold_out") : (
              <>
                {t("book_pay")}
                <ArrowRightIcon className="w-4 h-4" />
              </>
            )}
          </Button>
        </Authenticated>
        <Unauthenticated>
          <div className="space-y-1 text-right">
            <p className="text-xs text-muted-foreground">{t("auth.sign_in_to_book", { ns: "common" })}</p>
            <SignInButton />
          </div>
        </Unauthenticated>
      </div>

      {/* Booking dialog */}
      <Dialog open={dialogOpen} onOpenChange={setDialogOpen}>
        <DialogContent className="max-w-md max-h-[90vh] flex flex-col">
          <DialogHeader>
            <DialogTitle>{t("complete_booking")}</DialogTitle>
            <DialogDescription>
              {trip.originLoc?.city} → {trip.destLoc?.city} · {fmt(trip.departureTime, "EEE MMM d, HH:mm")}
            </DialogDescription>
          </DialogHeader>

          <div className="space-y-4 py-2 overflow-y-auto flex-1 min-h-0 pr-1">
            <div className="space-y-1.5">
              <Label htmlFor="pName">{t("passenger_name")}</Label>
              <Input
                id="pName"
                placeholder="John Smith"
                value={passengerName}
                onChange={(e) => setPassengerName(e.target.value)}
              />
            </div>
            <div className="space-y-1.5">
              <Label htmlFor="pPhone">{t("phone_optional")}</Label>
              <Input
                id="pPhone"
                placeholder="+237 6xx xxx xxx"
                value={passengerPhone}
                onChange={(e) => setPassengerPhone(e.target.value)}
              />
            </div>

            {/* Seat selection */}
            {trip.totalSeats > 0 && (
              <div className="space-y-1.5">
                <Label>{t("choose_seat", { defaultValue: "Choisir votre siège" })}</Label>
                <SeatPicker
                  totalSeats={trip.totalSeats}
                  occupiedSeats={occupiedSeats ?? []}
                  selectedSeat={selectedSeat}
                  onSelect={setSelectedSeat}
                  busType={trip.bus?.busType}
                />
              </div>
            )}

            <Separator />

            {/* Promo code input */}
            <div className="space-y-1.5">
              <Label>{t("promo_code", { defaultValue: "Code promo" })}</Label>
              <div className="flex gap-2">
                <Input
                  placeholder="e.g. SUMMER2025"
                  value={promoCode}
                  onChange={(e) => { setPromoCode(e.target.value.toUpperCase()); setPromoResult(null); }}
                  className="font-mono flex-1"
                />
                <Button
                  type="button"
                  size="sm"
                  variant="secondary"
                  disabled={!promoCode.trim() || validatingPromo}
                  onClick={handleValidatePromo}
                  className="cursor-pointer shrink-0"
                >
                  {validatingPromo ? "..." : t("apply", { defaultValue: "Appliquer" })}
                </Button>
              </div>
              {promoResult?.valid && (
                <p className="text-xs text-green-600 flex items-center gap-1">
                  <TagIcon className="w-3 h-3" />
                  -{trip.currency} {promoResult.discountAmount?.toLocaleString()} ({promoResult.code})
                </p>
              )}
            </div>

            <div className="flex items-center justify-between text-sm">
              <span className="text-muted-foreground">{t("labels.total_to_pay", { ns: "common" })}</span>
              <span className="font-bold text-primary text-lg">
                {trip.currency} {promoResult?.valid && promoResult.discountAmount
                  ? (trip.priceAmount - promoResult.discountAmount).toLocaleString()
                  : trip.priceAmount.toLocaleString()
                }
              </span>
            </div>

            <div className="flex items-center gap-2 rounded-lg bg-primary/5 border border-primary/20 px-3 py-2">
              <CreditCardIcon className="w-4 h-4 text-primary shrink-0" />
              <p className="text-xs text-muted-foreground">
                {t("geniuspay_info", { defaultValue: "You will be redirected to GeniusPay secure checkout to complete your payment." })}
              </p>
            </div>
          </div>

          <DialogFooter className="pt-2 border-t">
            <Button variant="ghost" onClick={() => setDialogOpen(false)} className="cursor-pointer">
              {t("buttons.cancel", { ns: "common" })}
            </Button>
            <Button onClick={handleBook} disabled={loading} className="cursor-pointer">
              {loading ? t("processing") : t("proceed_payment")}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  );
}
