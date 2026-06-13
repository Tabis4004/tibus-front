import { useEffect, useMemo, useState } from "react";
import { Link, useNavigate, useParams, useSearchParams } from "react-router-dom";
import {
  ArrowLeftIcon,
  ArrowRightIcon,
  CreditCardIcon,
  Loader2Icon,
  ShieldCheckIcon,
} from "lucide-react";
import { toast } from "sonner";
import { format, parseISO } from "date-fns";
import { useTranslation } from "react-i18next";
import { Button } from "@/components/ui/button.tsx";
import { Label } from "@/components/ui/label.tsx";
import { Skeleton } from "@/components/ui/skeleton.tsx";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select.tsx";
import {
  Authenticated,
  AuthLoading,
  Unauthenticated,
} from "@/components/auth/AuthBoundary.tsx";
import { SignInButton } from "@/components/ui/signin.tsx";
import { usePaymentCountryNetworks } from "@/hooks/use-payment-country-networks";
import { useSupabaseTripDetail } from "@/hooks/use-supabase-trip-detail";
import type { PaymentBreakdown, PaymentGateway, PaymentNetwork } from "@/config/commission.ts";
import { paymentNetworkLabel } from "@/lib/payment-networks.ts";
import {
  clearBookingDraft,
  loadBookingDraft,
  saveBookingDraft,
} from "@/lib/supabase/booking-draft";
import { checkTripAvailabilitySupabase } from "@/lib/supabase/trip-detail";
import { getActivePaymentGatewaySupabase } from "@/lib/supabase/payment-gateway.ts";
import { calculateTravelerPaymentSupabase } from "@/lib/supabase/payment-fees";
import { initializePaymentSupabase } from "@/lib/supabase/payments.ts";
import {
  DEFAULT_TRAVELER_PAYMENT_NOTICE,
  getTravelerPaymentNoticeSupabase,
  type TravelerPaymentNotice,
} from "@/lib/supabase/traveler-payment-notice.ts";
import { supabaseErrorMessage } from "@/lib/supabase/errors";

function fmt(iso: string, pattern: string) {
  try {
    return format(parseISO(iso), pattern);
  } catch {
    return iso;
  }
}

function PaymentSetupInner() {
  const { t } = useTranslation("traveler");
  const { lng } = useParams<{ lng: string }>();
  const navigate = useNavigate();
  const [searchParams] = useSearchParams();
  const reservationId = searchParams.get("reservationId") ?? "";

  const trip = useSupabaseTripDetail(reservationId || undefined);
  const [draft, setDraft] = useState(() =>
    reservationId ? loadBookingDraft(reservationId) : null,
  );
  const [activeGateway, setActiveGateway] = useState<PaymentGateway>("fedapay");
  const [paymentBreakdown, setPaymentBreakdown] = useState<PaymentBreakdown | null>(null);
  const [paymentPreviewLoading, setPaymentPreviewLoading] = useState(false);
  const [paymentPreviewError, setPaymentPreviewError] = useState<string | null>(null);
  const [paymentNotice, setPaymentNotice] = useState<TravelerPaymentNotice>(
    DEFAULT_TRAVELER_PAYMENT_NOTICE,
  );
  const [paying, setPaying] = useState(false);

  const {
    countries: paymentCountries,
    paymentCountryId,
    paymentCountryName,
    paymentNetwork,
    paymentNetworkOptions,
    networksLoading,
    selectPaymentCountry,
    selectPaymentNetwork,
    setPaymentCountryId,
    setPaymentNetwork,
  } = usePaymentCountryNetworks({
    activeGateway,
    passengerPhone: draft?.passengerPhone ?? "",
  });

  useEffect(() => {
    if (!reservationId) return;
    const loaded = loadBookingDraft(reservationId);
    if (loaded) setDraft(loaded);
  }, [reservationId]);

  useEffect(() => {
    if (!draft?.paymentCountryId) return;
    setPaymentCountryId(draft.paymentCountryId);
  }, [draft?.paymentCountryId, setPaymentCountryId]);

  useEffect(() => {
    if (!draft?.paymentNetwork) return;
    setPaymentNetwork(draft.paymentNetwork as PaymentNetwork);
  }, [draft?.paymentNetwork, setPaymentNetwork]);

  useEffect(() => {
    void getTravelerPaymentNoticeSupabase()
      .then(setPaymentNotice)
      .catch(() => setPaymentNotice(DEFAULT_TRAVELER_PAYMENT_NOTICE));
  }, []);

  useEffect(() => {
    void getActivePaymentGatewaySupabase()
      .then((state) => setActiveGateway(state.gateway))
      .catch(() => setActiveGateway("fedapay"));
  }, []);

  const nominalAmount = useMemo(() => {
    if (!trip) return 0;
    return Math.max(
      0,
      trip.priceAmount
        - (draft?.discountAmount ?? 0)
        - (draft?.loyaltyDiscountAmount ?? 0)
        - (draft?.platformLoyaltyDiscountAmount ?? 0),
    );
  }, [draft, trip]);

  useEffect(() => {
    if (!trip?.companyId || !paymentCountryId || !paymentNetwork) {
      setPaymentBreakdown(null);
      setPaymentPreviewError(null);
      return;
    }

    let cancelled = false;
    setPaymentPreviewLoading(true);
    setPaymentPreviewError(null);

    calculateTravelerPaymentSupabase({
      nominalAmount,
      companyId: trip.companyId,
      countryId: paymentCountryId,
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
    nominalAmount,
    paymentCountryId,
    paymentNetwork,
    activeGateway,
  ]);

  const persistDraft = () => {
    if (!reservationId || !draft) return;
    saveBookingDraft({
      ...draft,
      paymentCountryId,
      paymentNetwork,
      savedAt: new Date().toISOString(),
    });
  };

  const handleContinueLater = () => {
    persistDraft();
    toast.success(
      "Vos informations sont sauvegardées sur cet appareil. Le siège n'est pas garanti — revenez payer dès que possible.",
    );
    navigate(`/${lng ?? "fr"}/trip/${reservationId}`);
  };

  const handlePay = async () => {
    if (!reservationId || !draft?.passengerName.trim()) {
      toast.error("Informations de réservation manquantes");
      return;
    }
    if (!paymentCountryId) {
      toast.error("Choisissez le pays de paiement");
      return;
    }
    if (!paymentNetwork || paymentNetwork === "unknown") {
      toast.error("Choisissez votre réseau Mobile Money");
      return;
    }
    const phone = draft.passengerPhone.trim();
    if (!phone || phone.replace(/\D/g, "").length < 9) {
      toast.error("Numéro de téléphone invalide");
      return;
    }

    setPaying(true);
    try {
      const availability = await checkTripAvailabilitySupabase(reservationId);
      if (!availability.available) {
        toast.error("Plus de places disponibles sur ce départ");
        return;
      }

      persistDraft();

      const baseUrl = window.location.origin;
      const successUrl = `${baseUrl}/${lng}/payment/verify?reservationId=${reservationId}&gateway=${activeGateway}`;
      const errorUrl = `${baseUrl}/${lng}/payment/verify?status=failed&reservationId=${reservationId}&gateway=${activeGateway}`;

      const { checkoutUrl } = await initializePaymentSupabase({
        reservationId,
        passengerName: draft.passengerName.trim(),
        passengerPhone: phone,
        seatNumber: draft.selectedSeat ?? undefined,
        promoId: draft.promoId,
        discountAmount: draft.discountAmount,
        loyaltyPointsRedeemed: draft.loyaltyPointsRedeemed,
        loyaltyDiscountAmount: draft.loyaltyDiscountAmount,
        platformLoyaltyPointsRedeemed: draft.platformLoyaltyPointsRedeemed,
        platformLoyaltyDiscountAmount: draft.platformLoyaltyDiscountAmount,
        paymentCountryId,
        paymentNetwork,
        successUrl,
        errorUrl,
      });

      window.location.href = checkoutUrl;
    } catch (err) {
      toast.error(supabaseErrorMessage(err, t("errors.generic", { ns: "common" })));
      setPaying(false);
    }
  };

  if (!reservationId) {
    return (
      <div className="max-w-lg mx-auto px-4 py-16 text-center space-y-4">
        <p className="text-muted-foreground">Réservation introuvable.</p>
        <Button asChild variant="outline">
          <Link to={`/${lng ?? "fr"}/traveler/search`}>Rechercher un trajet</Link>
        </Button>
      </div>
    );
  }

  if (!draft) {
    return (
      <div className="max-w-lg mx-auto px-4 py-16 text-center space-y-4">
        <p className="text-muted-foreground">
          Aucune réservation en cours. Complétez d'abord vos informations sur le trajet.
        </p>
        <Button asChild>
          <Link to={`/${lng ?? "fr"}/trip/${reservationId}`}>Retour au trajet</Link>
        </Button>
      </div>
    );
  }

  if (!trip) {
    return (
      <div className="max-w-lg mx-auto px-4 py-8 space-y-4">
        <Skeleton className="h-8 w-48" />
        <Skeleton className="h-40 w-full" />
        <Skeleton className="h-12 w-full" />
      </div>
    );
  }

  return (
    <div className="max-w-lg mx-auto px-4 py-6 space-y-6">
      <button
        type="button"
        onClick={() => navigate(`/${lng ?? "fr"}/trip/${reservationId}`)}
        className="inline-flex items-center gap-2 text-sm text-muted-foreground hover:text-foreground"
      >
        <ArrowLeftIcon className="w-4 h-4" />
        Retour au trajet
      </button>

      <div className="space-y-1">
        <h1 className="text-2xl font-bold tracking-tight">Paiement Mobile Money</h1>
        <p className="text-sm text-muted-foreground">
          {trip.originLoc?.city} → {trip.destLoc?.city} · {fmt(trip.departureTime, "EEE d MMM, HH:mm")}
        </p>
      </div>

      <div className="rounded-xl border p-4 space-y-3 bg-muted/20">
        <div className="flex items-start gap-2">
          <ShieldCheckIcon className="mt-0.5 h-4 w-4 shrink-0 text-amber-600" />
          <p className="text-sm leading-snug">{paymentNotice.infoLine}</p>
        </div>
        <p className="text-sm text-muted-foreground">{paymentNotice.paragraph1}</p>
      </div>

      <div className="rounded-xl border p-4 space-y-4">
        <div className="space-y-1 text-sm">
          <p><span className="text-muted-foreground">Voyageur :</span> {draft.passengerName}</p>
          <p><span className="text-muted-foreground">Téléphone :</span> {draft.passengerPhone}</p>
          {draft.selectedSeat ? (
            <p><span className="text-muted-foreground">Siège :</span> {draft.selectedSeat}</p>
          ) : null}
        </div>

        <div className="space-y-1.5">
          <Label>Pays de paiement *</Label>
          <Select value={paymentCountryId || undefined} onValueChange={selectPaymentCountry}>
            <SelectTrigger>
              <SelectValue placeholder="Choisissez le pays de votre portefeuille" />
            </SelectTrigger>
            <SelectContent>
              {(paymentCountries ?? []).map((country) => (
                <SelectItem key={country.id} value={country.id}>
                  {country.name}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
          {!paymentCountries ? (
            <p className="text-xs text-muted-foreground">Chargement des pays...</p>
          ) : paymentCountries.length === 0 ? (
            <p className="text-xs text-destructive">Aucun pays de paiement configuré.</p>
          ) : (
            <p className="text-xs text-muted-foreground">
              Sélectionnez le pays où est enregistré votre compte Mobile Money.
            </p>
          )}
        </div>

        <div className="space-y-1.5">
          <Label>Réseau Mobile Money *</Label>
          <Select
            value={paymentNetwork}
            onValueChange={(value) => selectPaymentNetwork(value as PaymentNetwork)}
            disabled={!paymentCountryId || networksLoading || paymentNetworkOptions.length === 0}
          >
            <SelectTrigger>
              <SelectValue
                placeholder={
                  paymentCountryId
                    ? "Choisissez Orange, MTN, Wave..."
                    : "Choisissez d'abord un pays"
                }
              />
            </SelectTrigger>
            <SelectContent>
              {paymentNetworkOptions.map((option) => (
                <SelectItem key={option.value} value={option.value}>
                  {paymentNetworkLabel(option.value, lng ?? "fr")}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
          {paymentCountryName && paymentNetworkOptions.length === 0 && !networksLoading ? (
            <p className="text-xs text-destructive">
              Aucun réseau configuré pour {paymentCountryName}.
            </p>
          ) : null}
        </div>

        <div className="rounded-lg border bg-background p-3 flex items-center justify-between">
          <div>
            <p className="text-xs text-muted-foreground">Total à payer</p>
            <p className="text-2xl font-black text-primary">
              {paymentPreviewLoading
                ? "..."
                : `${trip.currency} ${(paymentBreakdown?.totalAmount ?? nominalAmount).toLocaleString()}`}
            </p>
          </div>
          <CreditCardIcon className="w-8 h-8 text-muted-foreground/40" />
        </div>

        {paymentPreviewError ? (
          <p className="text-xs text-amber-700">
            {paymentPreviewError.includes("Configuration frais gateway")
              ? "Frais non configurés pour ce pays/réseau — choisissez une autre combinaison."
              : paymentPreviewError}
          </p>
        ) : null}
      </div>

      <div className="flex flex-col gap-2 sm:flex-row">
        <Button
          variant="outline"
          className="flex-1 cursor-pointer"
          onClick={handleContinueLater}
          disabled={paying}
        >
          Continuer plus tard
        </Button>
        <Button
          className="flex-1 cursor-pointer gap-2"
          onClick={() => void handlePay()}
          disabled={paying || !paymentCountryId || paymentNetwork === "unknown"}
        >
          {paying ? (
            <>
              <Loader2Icon className="w-4 h-4 animate-spin" />
              Redirection...
            </>
          ) : (
            <>
              Payer maintenant
              <ArrowRightIcon className="w-4 h-4" />
            </>
          )}
        </Button>
      </div>
    </div>
  );
}

export default function SupabasePaymentSetup() {
  return (
    <>
      <AuthLoading>
        <div className="max-w-lg mx-auto px-4 py-16">
          <Skeleton className="h-40 w-full" />
        </div>
      </AuthLoading>
      <Unauthenticated>
        <div className="max-w-lg mx-auto px-4 py-16 text-center space-y-4">
          <p className="text-muted-foreground">Connectez-vous pour payer votre billet.</p>
          <SignInButton />
        </div>
      </Unauthenticated>
      <Authenticated>
        <PaymentSetupInner />
      </Authenticated>
    </>
  );
}
