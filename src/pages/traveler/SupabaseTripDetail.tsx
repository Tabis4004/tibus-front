import { useEffect, useState } from "react";
import { useParams, useNavigate } from "react-router-dom";
import {
  ArrowLeftIcon,
  BusIcon,
  MapPinIcon,
  UsersIcon,
  BuildingIcon,
  CheckCircleIcon,
  CreditCardIcon,
  RouteIcon,
  ShieldCheckIcon,
  ArrowRightIcon,
  TagIcon,
  GiftIcon,
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
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
} from "@/components/ui/alert-dialog.tsx";
import { toast } from "sonner";
import { format, parseISO } from "date-fns";
import { useSupabaseAuth } from "@/components/providers/supabase-auth";
import { useAppUser } from "@/hooks/use-app-user.ts";
import {
  useSupabaseTripDetail,
  useSupabaseOccupiedSeats,
} from "@/hooks/use-supabase-trip-detail";
import {
  checkTripAvailabilitySupabase,
  validatePromoCodeSupabase,
} from "@/lib/supabase/trip-detail";
import { validateLoyaltyRedemptionSupabase } from "@/lib/supabase/loyalty.ts";
import {
  getLoyaltyBookingContextSupabase,
  validatePlatformLoyaltyRedemptionSupabase,
  type LoyaltyBookingContext,
} from "@/lib/supabase/platform-loyalty.ts";
import {
  clearBookingDraft,
  loadBookingDraft,
  saveBookingDraft,
} from "@/lib/supabase/booking-draft";
import { getActivePaymentGatewaySupabase } from "@/lib/supabase/payment-gateway.ts";
import { initializePaymentSupabase } from "@/lib/supabase/payments.ts";
import {
  calculateTravelerPaymentSupabase,
} from "@/lib/supabase/payment-fees";
import type { PaymentBreakdown, PaymentGateway, PaymentNetwork } from "@/config/commission.ts";
import {
  inferCiNetworkFromPhone,
  PAYMENT_NETWORK_OPTIONS,
  paymentNetworkLabel,
} from "@/lib/payment-networks.ts";
import {
  DEFAULT_TRAVELER_PAYMENT_NOTICE,
  getTravelerPaymentNoticeSupabase,
  type TravelerPaymentNotice,
} from "@/lib/supabase/traveler-payment-notice.ts";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select.tsx";
import {
  Authenticated,
  Unauthenticated,
} from "@/components/auth/AuthBoundary.tsx";
import { SignInButton } from "@/components/ui/signin.tsx";
import { useTranslation } from "react-i18next";
import SeatPicker from "@/components/seat-picker.tsx";
import { supabaseErrorMessage } from "@/lib/supabase/errors";

function fmt(iso: string, pattern: string) {
  try { return format(parseISO(iso), pattern); } catch { return iso; }
}

export default function SupabaseTripDetail() {
  const { t } = useTranslation("traveler");
  const { tripId, lng } = useParams<{ tripId: string; lng: string }>();
  const navigate = useNavigate();
  const { appUserId } = useSupabaseAuth();
  const appUser = useAppUser();
  const trip = useSupabaseTripDetail(tripId);

  const [dialogOpen, setDialogOpen] = useState(false);
  const [passengerName, setPassengerName] = useState("");
  const [passengerPhone, setPassengerPhone] = useState("");
  const [selectedSeat, setSelectedSeat] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);
  const [promoCode, setPromoCode] = useState("");
  const [promoResult, setPromoResult] = useState<{ valid: boolean; promoId?: string; discountAmount?: number; code?: string; error?: string } | null>(null);
  const [validatingPromo, setValidatingPromo] = useState(false);
  const [loyaltyContext, setLoyaltyContext] = useState<LoyaltyBookingContext | null>(null);
  const [companyLoyaltyPointsInput, setCompanyLoyaltyPointsInput] = useState("");
  const [companyLoyaltyResult, setCompanyLoyaltyResult] = useState<{ valid: boolean; discountAmount?: number; pointsRedeemed?: number; error?: string } | null>(null);
  const [platformLoyaltyPointsInput, setPlatformLoyaltyPointsInput] = useState("");
  const [platformLoyaltyResult, setPlatformLoyaltyResult] = useState<{ valid: boolean; discountAmount?: number; pointsRedeemed?: number; error?: string } | null>(null);
  const [validatingCompanyLoyalty, setValidatingCompanyLoyalty] = useState(false);
  const [validatingPlatformLoyalty, setValidatingPlatformLoyalty] = useState(false);
  const [seatTakenOpen, setSeatTakenOpen] = useState(false);
  const [continueLaterOpen, setContinueLaterOpen] = useState(false);
  const [paymentBreakdown, setPaymentBreakdown] = useState<PaymentBreakdown | null>(null);
  const [paymentPreviewLoading, setPaymentPreviewLoading] = useState(false);
  const [paymentPreviewError, setPaymentPreviewError] = useState<string | null>(null);
  const [paymentNetwork, setPaymentNetwork] = useState<PaymentNetwork>("unknown");
  const [networkManual, setNetworkManual] = useState(false);
  const [activeGateway, setActiveGateway] = useState<PaymentGateway>("fedapay");
  const [paymentNotice, setPaymentNotice] = useState<TravelerPaymentNotice>(
    DEFAULT_TRAVELER_PAYMENT_NOTICE,
  );

  const occupiedSeats = useSupabaseOccupiedSeats(tripId);

  useEffect(() => {
    void getTravelerPaymentNoticeSupabase()
      .then(setPaymentNotice)
      .catch(() => setPaymentNotice(DEFAULT_TRAVELER_PAYMENT_NOTICE));
  }, []);

  useEffect(() => {
    if (!tripId) return;
    const draft = loadBookingDraft(tripId);
    if (!draft) return;
    setPassengerName(draft.passengerName);
    setPassengerPhone(draft.passengerPhone);
    setSelectedSeat(draft.selectedSeat);
    setPromoCode(draft.promoCode);
    if (draft.promoId && draft.discountAmount) {
      setPromoResult({
        valid: true,
        promoId: draft.promoId,
        discountAmount: draft.discountAmount,
        code: draft.promoCode,
      });
    }
    if (draft.loyaltyPointsRedeemed) {
      setCompanyLoyaltyPointsInput(String(draft.loyaltyPointsRedeemed));
      if (draft.loyaltyDiscountAmount) {
        setCompanyLoyaltyResult({
          valid: true,
          pointsRedeemed: draft.loyaltyPointsRedeemed,
          discountAmount: draft.loyaltyDiscountAmount,
        });
      }
    }
    if (draft.platformLoyaltyPointsRedeemed) {
      setPlatformLoyaltyPointsInput(String(draft.platformLoyaltyPointsRedeemed));
      if (draft.platformLoyaltyDiscountAmount) {
        setPlatformLoyaltyResult({
          valid: true,
          pointsRedeemed: draft.platformLoyaltyPointsRedeemed,
          discountAmount: draft.platformLoyaltyDiscountAmount,
        });
      }
    }
  }, [tripId]);

  useEffect(() => {
    if (!trip?.companyId || !appUserId) {
      setLoyaltyContext(null);
      return;
    }
    void getLoyaltyBookingContextSupabase(trip.companyId)
      .then(setLoyaltyContext)
      .catch(() => setLoyaltyContext({
        company: { active: false, pointsBalance: 0 },
        platform: { active: false, pointsBalance: 0 },
      }));
  }, [trip?.companyId, appUserId]);

  useEffect(() => {
    if (!tripId || !appUser.profile) return;
    const draft = loadBookingDraft(tripId);
    if (draft) return;

    const fullName = `${appUser.profile.firstName} ${appUser.profile.lastName}`.trim();
    setPassengerName(fullName);
    setPassengerPhone(appUser.profile.phone ?? "");
  }, [appUser.profile, tripId]);

  useEffect(() => {
    void getActivePaymentGatewaySupabase()
      .then((state) => setActiveGateway(state.gateway))
      .catch(() => setActiveGateway("fedapay"));
  }, []);

  useEffect(() => {
    if (networkManual) return;
    const inferred = inferCiNetworkFromPhone(passengerPhone);
    if (inferred) {
      setPaymentNetwork(inferred);
    }
  }, [passengerPhone, networkManual]);

  useEffect(() => {
    if (!trip?.companyId) {
      setPaymentBreakdown(null);
      setPaymentPreviewError(null);
      return;
    }

    const nominalAmount = Math.max(
      0,
      trip.priceAmount
        - (promoResult?.valid ? (promoResult.discountAmount ?? 0) : 0)
        - (companyLoyaltyResult?.valid ? (companyLoyaltyResult.discountAmount ?? 0) : 0)
        - (platformLoyaltyResult?.valid ? (platformLoyaltyResult.discountAmount ?? 0) : 0),
    );

    let cancelled = false;
    setPaymentPreviewLoading(true);
    setPaymentPreviewError(null);

    calculateTravelerPaymentSupabase({
      nominalAmount,
      companyId: trip.companyId,
      gateway: activeGateway,
      method: "mobile_money",
      network: paymentNetwork,
    })
      .then((breakdown) => {
        if (!cancelled) setPaymentBreakdown(breakdown);
      })
      .catch((err) => {
        if (!cancelled) {
          setPaymentBreakdown(null);
          setPaymentPreviewError(
            err instanceof Error ? err.message : "Calcul du montant impossible",
          );
        }
      })
      .finally(() => {
        if (!cancelled) setPaymentPreviewLoading(false);
      });

    return () => {
      cancelled = true;
    };
  }, [
    trip?.companyId,
    trip?.priceAmount,
    promoResult?.valid,
    promoResult?.discountAmount,
    companyLoyaltyResult?.valid,
    companyLoyaltyResult?.discountAmount,
    platformLoyaltyResult?.valid,
    platformLoyaltyResult?.discountAmount,
    paymentNetwork,
    activeGateway,
  ]);

  useEffect(() => {
    if (!tripId || !selectedSeat || !occupiedSeats?.includes(selectedSeat)) return;

    setSelectedSeat(null);

    const draft = loadBookingDraft(tripId);
    if (draft) {
      saveBookingDraft({
        ...draft,
        selectedSeat: null,
        savedAt: new Date().toISOString(),
      });
    }

    if (dialogOpen) {
      setSeatTakenOpen(true);
    }
  }, [dialogOpen, occupiedSeats, selectedSeat, tripId]);

  const priceAfterPromo = Math.max(
    0,
    (trip?.priceAmount ?? 0) - (promoResult?.valid ? (promoResult.discountAmount ?? 0) : 0),
  );

  const handleValidateCompanyLoyalty = async () => {
    if (!trip) return;
    const points = Number(companyLoyaltyPointsInput);
    if (!Number.isFinite(points) || points <= 0) {
      setCompanyLoyaltyResult({ valid: true, discountAmount: 0, pointsRedeemed: 0 });
      return;
    }
    setValidatingCompanyLoyalty(true);
    try {
      const result = await validateLoyaltyRedemptionSupabase(trip.companyId, priceAfterPromo, points);
      setCompanyLoyaltyResult(result);
      if (!result.valid) {
        toast.error(result.error ?? "Points compagnie invalides");
      }
    } catch {
      setCompanyLoyaltyResult(null);
      toast.error(t("errors.generic", { ns: "common" }));
    } finally {
      setValidatingCompanyLoyalty(false);
    }
  };

  const handleValidatePlatformLoyalty = async () => {
    if (!trip) return;
    const points = Number(platformLoyaltyPointsInput);
    if (!Number.isFinite(points) || points <= 0) {
      setPlatformLoyaltyResult({ valid: true, discountAmount: 0, pointsRedeemed: 0 });
      return;
    }
    setValidatingPlatformLoyalty(true);
    try {
      const priceAfterCompany = Math.max(
        0,
        priceAfterPromo - (companyLoyaltyResult?.valid ? (companyLoyaltyResult.discountAmount ?? 0) : 0),
      );
      const result = await validatePlatformLoyaltyRedemptionSupabase(priceAfterCompany, points);
      setPlatformLoyaltyResult(result);
      if (!result.valid) {
        toast.error(result.error ?? "Points plateforme invalides");
      }
    } catch {
      setPlatformLoyaltyResult(null);
      toast.error(t("errors.generic", { ns: "common" }));
    } finally {
      setValidatingPlatformLoyalty(false);
    }
  };

  const handleValidatePromo = async () => {
    if (!promoCode.trim() || !trip) return;
    setValidatingPromo(true);
    try {
      const result = await validatePromoCodeSupabase(
        promoCode.trim(),
        trip.priceAmount,
        trip.trajetId,
        trip.companyId,
      );
      setPromoResult(result);
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
    if (!tripId) {
      toast.error(t("errors.generic", { ns: "common" }));
      return;
    }
    if (trip.totalSeats > 0 && !selectedSeat) {
      toast.error("Choisissez un siège avant de payer");
      return;
    }
    if (selectedSeat && occupiedSeats?.includes(selectedSeat)) {
      setSeatTakenOpen(true);
      return;
    }

    setLoading(true);
    try {
      const availability = await checkTripAvailabilitySupabase(tripId);
      if (!availability.available) {
        setSeatTakenOpen(true);
        return;
      }
      setContinueLaterOpen(true);
    } catch {
      toast.error(t("errors.generic", { ns: "common" }));
    } finally {
      setLoading(false);
    }
  };

  const handleContinueLater = () => {
    if (!tripId) return;
    saveBookingDraft({
      reservationId: tripId,
      passengerName: passengerName.trim(),
      passengerPhone: passengerPhone.trim(),
      selectedSeat,
      promoCode,
      promoId: promoResult?.valid ? promoResult.promoId : undefined,
      discountAmount: promoResult?.valid ? promoResult.discountAmount : undefined,
      loyaltyPointsRedeemed: companyLoyaltyResult?.valid ? companyLoyaltyResult.pointsRedeemed : undefined,
      loyaltyDiscountAmount: companyLoyaltyResult?.valid ? companyLoyaltyResult.discountAmount : undefined,
      platformLoyaltyPointsRedeemed: platformLoyaltyResult?.valid ? platformLoyaltyResult.pointsRedeemed : undefined,
      platformLoyaltyDiscountAmount: platformLoyaltyResult?.valid ? platformLoyaltyResult.discountAmount : undefined,
      savedAt: new Date().toISOString(),
    });
    setContinueLaterOpen(false);
    setDialogOpen(false);
    toast.success(
      "Vos informations sont sauvegardées sur cet appareil. Le siège n'est pas garanti — revenez payer dès que possible.",
    );
  };

  const handlePayNow = async () => {
    if (!tripId || !passengerName.trim()) return;
    if (trip.totalSeats > 0 && !selectedSeat) {
      toast.error("Choisissez un siège avant de payer");
      return;
    }
    if (selectedSeat && occupiedSeats?.includes(selectedSeat)) {
      setSeatTakenOpen(true);
      return;
    }

    const phone = passengerPhone.trim();
    if (!phone) {
      toast.error("Numéro de téléphone requis pour payer");
      return;
    }
    const digits = phone.replace(/\D/g, "");
    if (digits.length < 9) {
      toast.error("Numéro trop court — ex: 07 00 00 00 00 ou +225 07...");
      return;
    }

    setContinueLaterOpen(false);
    setLoading(true);

    try {
      const availability = await checkTripAvailabilitySupabase(tripId);
      if (!availability.available) {
        setSeatTakenOpen(true);
        return;
      }

      const baseUrl = window.location.origin;
      const successUrl = `${baseUrl}/${lng}/payment/verify?reservationId=${tripId}&gateway=${activeGateway}`;
      const errorUrl = `${baseUrl}/${lng}/payment/verify?status=failed&reservationId=${tripId}&gateway=${activeGateway}`;

      const { checkoutUrl } = await initializePaymentSupabase({
        reservationId: tripId,
        passengerName: passengerName.trim(),
        passengerPhone: phone,
        seatNumber: selectedSeat ?? undefined,
        promoId: promoResult?.valid ? promoResult.promoId : undefined,
        discountAmount: promoResult?.valid ? promoResult.discountAmount : undefined,
        loyaltyPointsRedeemed: companyLoyaltyResult?.valid ? companyLoyaltyResult.pointsRedeemed : undefined,
        loyaltyDiscountAmount: companyLoyaltyResult?.valid ? companyLoyaltyResult.discountAmount : undefined,
        platformLoyaltyPointsRedeemed: platformLoyaltyResult?.valid ? platformLoyaltyResult.pointsRedeemed : undefined,
        platformLoyaltyDiscountAmount: platformLoyaltyResult?.valid ? platformLoyaltyResult.discountAmount : undefined,
        paymentNetwork,
        successUrl,
        errorUrl,
      });

      window.location.href = checkoutUrl;
    } catch (err) {
      const error = err as Error & { code?: string };
      if (error.code === "SOLD_OUT") {
        setSeatTakenOpen(true);
        return;
      }
      toast.error(supabaseErrorMessage(error, t("errors.generic", { ns: "common" })));
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
                readOnly
                className="bg-muted/60"
                onChange={(e) => setPassengerName(e.target.value)}
              />
              <p className="text-[11px] text-muted-foreground">
                Les voyageurs réservent uniquement pour leur propre profil.
              </p>
            </div>
            <div className="space-y-1.5">
              <Label htmlFor="pPhone">Téléphone</Label>
              <Input
                id="pPhone"
                placeholder="+225 07 00 00 00 00"
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

            <div className="space-y-1.5">
              <Label>Réseau Mobile Money</Label>
              <Select
                value={paymentNetwork}
                onValueChange={(value) => {
                  setNetworkManual(true);
                  setPaymentNetwork(value as PaymentNetwork);
                }}
              >
                <SelectTrigger>
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  {PAYMENT_NETWORK_OPTIONS.map((option) => (
                    <SelectItem key={option.value} value={option.value}>
                      {paymentNetworkLabel(option.value, lng ?? "fr")}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
              {paymentBreakdown?.usedMaxFallback && (
                <p className="text-xs text-muted-foreground">
                  Estimation avec le taux le plus élevé ({paymentBreakdown.network}).
                </p>
              )}
            </div>

            <Separator />

            {loyaltyContext?.company.active ? (
              <div className="space-y-1.5">
                <Label className="flex items-center gap-1.5">
                  <GiftIcon className="w-3.5 h-3.5" />
                  {t("company_loyalty_points", { defaultValue: "Points compagnie" })}
                </Label>
                <p className="text-xs text-muted-foreground">
                  {t("loyalty_balance", {
                    defaultValue: "Solde : {{points}} points",
                    points: loyaltyContext.company.pointsBalance,
                  })}
                </p>
                <div className="flex gap-2">
                  <Input
                    type="number"
                    min={0}
                    max={loyaltyContext.company.pointsBalance}
                    placeholder={String(loyaltyContext.company.minRedeemPoints ?? 0)}
                    value={companyLoyaltyPointsInput}
                    onChange={(e) => {
                      setCompanyLoyaltyPointsInput(e.target.value);
                      setCompanyLoyaltyResult(null);
                    }}
                    className="flex-1"
                  />
                  <Button
                    type="button"
                    size="sm"
                    variant="secondary"
                    disabled={validatingCompanyLoyalty}
                    onClick={() => void handleValidateCompanyLoyalty()}
                    className="cursor-pointer shrink-0"
                  >
                    {validatingCompanyLoyalty ? "..." : t("apply", { defaultValue: "Appliquer" })}
                  </Button>
                </div>
                {companyLoyaltyResult?.valid && (companyLoyaltyResult.discountAmount ?? 0) > 0 ? (
                  <p className="text-xs text-green-600 flex items-center gap-1">
                    <GiftIcon className="w-3 h-3" />
                    -{trip.currency} {companyLoyaltyResult.discountAmount?.toLocaleString()} ({companyLoyaltyResult.pointsRedeemed} pts)
                  </p>
                ) : null}
              </div>
            ) : null}

            {loyaltyContext?.platform.active ? (
              <div className="space-y-1.5">
                <Label className="flex items-center gap-1.5">
                  <GiftIcon className="w-3.5 h-3.5" />
                  {t("platform_loyalty_points", { defaultValue: "Points Tibus" })}
                </Label>
                <p className="text-xs text-muted-foreground">
                  {t("loyalty_balance", {
                    defaultValue: "Solde : {{points}} points",
                    points: loyaltyContext.platform.pointsBalance,
                  })}
                </p>
                <div className="flex gap-2">
                  <Input
                    type="number"
                    min={0}
                    max={loyaltyContext.platform.pointsBalance}
                    placeholder={String(loyaltyContext.platform.minRedeemPoints ?? 0)}
                    value={platformLoyaltyPointsInput}
                    onChange={(e) => {
                      setPlatformLoyaltyPointsInput(e.target.value);
                      setPlatformLoyaltyResult(null);
                    }}
                    className="flex-1"
                  />
                  <Button
                    type="button"
                    size="sm"
                    variant="secondary"
                    disabled={validatingPlatformLoyalty}
                    onClick={() => void handleValidatePlatformLoyalty()}
                    className="cursor-pointer shrink-0"
                  >
                    {validatingPlatformLoyalty ? "..." : t("apply", { defaultValue: "Appliquer" })}
                  </Button>
                </div>
                {platformLoyaltyResult?.valid && (platformLoyaltyResult.discountAmount ?? 0) > 0 ? (
                  <p className="text-xs text-green-600 flex items-center gap-1">
                    <GiftIcon className="w-3 h-3" />
                    -{trip.currency} {platformLoyaltyResult.discountAmount?.toLocaleString()} ({platformLoyaltyResult.pointsRedeemed} pts)
                  </p>
                ) : null}
              </div>
            ) : null}

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

            <div className="space-y-1.5 text-sm">
              <div className="flex items-center justify-between">
                <span className="text-muted-foreground">
                  {t("labels.ticket_price", { ns: "common", defaultValue: "Prix billet" })}
                </span>
                <span>
                  {trip.currency}{" "}
                  {(
                    trip.priceAmount
                    - (promoResult?.valid ? (promoResult.discountAmount ?? 0) : 0)
                    - (companyLoyaltyResult?.valid ? (companyLoyaltyResult.discountAmount ?? 0) : 0)
                    - (platformLoyaltyResult?.valid ? (platformLoyaltyResult.discountAmount ?? 0) : 0)
                  ).toLocaleString()}
                </span>
              </div>
              <div className="flex items-center justify-between">
                <span className="text-muted-foreground">{t("labels.total_to_pay", { ns: "common" })}</span>
                <span className="font-bold text-primary text-lg">
                  {paymentPreviewLoading
                    ? "..."
                    : `${trip.currency} ${(
                        paymentBreakdown?.totalAmount ??
                        (trip.priceAmount
                          - (promoResult?.valid ? (promoResult.discountAmount ?? 0) : 0)
                          - (companyLoyaltyResult?.valid ? (companyLoyaltyResult.discountAmount ?? 0) : 0)
                          - (platformLoyaltyResult?.valid ? (platformLoyaltyResult.discountAmount ?? 0) : 0))
                      ).toLocaleString()}`}
                </span>
              </div>
              {paymentPreviewError && (
                <p className="text-xs text-amber-700">
                  {paymentPreviewError.includes("Configuration frais gateway")
                    ? "Frais de paiement non configurés — le montant affiché est indicatif."
                    : paymentPreviewError}
                </p>
              )}
            </div>

            <div className="flex items-center gap-2 rounded-lg bg-amber-500/5 border border-amber-500/20 px-3 py-2">
              <ShieldCheckIcon className="w-4 h-4 text-amber-600 shrink-0" />
              <p className="text-xs text-muted-foreground">
                {t("geniuspay_info", {
                  defaultValue:
                    "You will be redirected to GeniusPay secure checkout. No seat is held and no ticket is issued until payment is confirmed.",
                })}
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

      <AlertDialog open={seatTakenOpen} onOpenChange={setSeatTakenOpen}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Siège plus disponible</AlertDialogTitle>
            <AlertDialogDescription>
              Désolé, ce départ est complet ou le siège vient d'être pris par un autre voyageur.
              Aucune réservation n'a été enregistrée.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogAction
              className="cursor-pointer"
              onClick={() => navigate(`/${lng}/traveler/search`)}
            >
              Rechercher un autre trajet
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>

      <AlertDialog open={continueLaterOpen} onOpenChange={setContinueLaterOpen}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>{paymentNotice.title}</AlertDialogTitle>
            <AlertDialogDescription asChild>
              <div className="space-y-3 text-sm text-muted-foreground">
                <p>{paymentNotice.paragraph1}</p>
                <p>1. {paymentNotice.paragraph2}</p>
                <div className="space-y-1.5">
                  <p>2. {paymentNotice.networkIntro}</p>
                  {paymentNotice.hints.length > 0 && (
                    <ul className="list-none space-y-1">
                      {paymentNotice.hints.map((hint) => (
                        <li key={`${hint.countryCode}-${hint.cheapestNetwork}`}>
                          <span className="font-medium">{hint.countryCode}</span>
                          {" → "}
                          {paymentNetworkLabel(
                            hint.cheapestNetwork as PaymentNetwork,
                            lng ?? "fr",
                          )}
                        </li>
                      ))}
                    </ul>
                  )}
                </div>
              </div>
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel className="cursor-pointer" onClick={handleContinueLater}>
              Continuer plus tard
            </AlertDialogCancel>
            <AlertDialogAction className="cursor-pointer" onClick={handlePayNow}>
              Payer maintenant
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </div>
  );
}
