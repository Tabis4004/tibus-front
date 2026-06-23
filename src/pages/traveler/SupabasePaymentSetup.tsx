import { useEffect, useMemo, useState } from "react";
import { Link, useNavigate, useParams, useSearchParams } from "react-router-dom";
import {
  ArrowLeftIcon,
  ArrowRightIcon,
  CreditCardIcon,
  Loader2Icon,
  MapPinIcon,
  ShieldCheckIcon,
} from "lucide-react";
import { toast } from "sonner";
import { format, parseISO } from "date-fns";
import { useTranslation } from "react-i18next";
import { Button } from "@/components/ui/button.tsx";
import { Label } from "@/components/ui/label.tsx";
import { Skeleton } from "@/components/ui/skeleton.tsx";
import { cn } from "@/lib/utils.ts";
import {
  Authenticated,
  AuthLoading,
  Unauthenticated,
} from "@/components/auth/AuthBoundary.tsx";
import { SignInButton } from "@/components/ui/signin.tsx";
import { usePaymentCountryNetworks } from "@/hooks/use-payment-country-networks";
import { useSupabaseTripDetail } from "@/hooks/use-supabase-trip-detail";
import {
  type PaymentBreakdown,
  type PaymentGateway,
  type PaymentMethod,
  type PaymentNetwork,
} from "@/config/commission.ts";
import { paymentNetworkLabel } from "@/lib/payment-networks.ts";
import {
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
import {
  getPayAtStationConfigSupabase,
  calculateStationBookingFeeSupabase,
  getPayAtStationReceiptMsgSupabase,
  DEFAULT_STATION_RECEIPT_MSG,
  type StationBookingFee,
  type PayAtStationReceiptMsg,
} from "@/lib/supabase/pay-at-station.ts";
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
  const [activeGateway, setActiveGateway] = useState<PaymentGateway>("geniuspay");
  const [paymentBreakdown, setPaymentBreakdown] = useState<PaymentBreakdown | null>(null);
  const [paymentPreviewLoading, setPaymentPreviewLoading] = useState(false);
  const [paymentPreviewError, setPaymentPreviewError] = useState<string | null>(null);
  const [paymentNotice, setPaymentNotice] = useState<TravelerPaymentNotice>(
    DEFAULT_TRAVELER_PAYMENT_NOTICE,
  );
  const [paying, setPaying] = useState(false);

  // ── Pay-at-station state ──
  const [isStationMode, setIsStationMode]           = useState(false);
  const [stationFee, setStationFee]                 = useState<StationBookingFee | null>(null);
  const [stationFeeLoading, setStationFeeLoading]   = useState(false);
  const [receiptMsg, setReceiptMsg]                 = useState<PayAtStationReceiptMsg>(DEFAULT_STATION_RECEIPT_MSG);

  const isGeniusPayCheckout = activeGateway === "geniuspay";

  const {
    countries: paymentCountries,
    countriesError,
    paymentCountryId,
    paymentCountryName,
    paymentNetwork,
    paymentNetworkOptions,
    networksLoading,
    inferredCountryName,
    restorePaymentSelection,
    selectPaymentCountry,
    selectPaymentNetwork,
  } = usePaymentCountryNetworks({
    activeGateway,
    passengerPhone: draft?.passengerPhone ?? "",
  });

  const checkoutNetwork: PaymentNetwork = paymentNetwork;

  const phoneCountryMismatch =
    inferredCountryName &&
    paymentCountryName &&
    inferredCountryName !== paymentCountryName;

  const payDisabledReason = !paymentCountryId
    ? "Choisissez le pays de votre portefeuille Mobile Money."
    : checkoutNetwork === "unknown"
      ? "Choisissez votre réseau Mobile Money."
      : phoneCountryMismatch
        ? `Le numéro correspond à ${inferredCountryName}, pas à ${paymentCountryName}.`
        : null;

  useEffect(() => {
    if (!reservationId) return;
    const loaded = loadBookingDraft(reservationId);
    if (loaded) setDraft(loaded);
  }, [reservationId]);

  useEffect(() => {
    if (!draft?.paymentCountryId) return;
    if (!draft.paymentNetwork || draft.paymentNetwork === "unknown") return;
    restorePaymentSelection(draft.paymentCountryId, draft.paymentNetwork as PaymentNetwork);
  }, [
    draft?.paymentCountryId,
    draft?.paymentNetwork,
    restorePaymentSelection,
  ]);

  useEffect(() => {
    void getTravelerPaymentNoticeSupabase()
      .then(setPaymentNotice)
      .catch(() => setPaymentNotice(DEFAULT_TRAVELER_PAYMENT_NOTICE));
  }, []);

  useEffect(() => {
    void getActivePaymentGatewaySupabase()
      .then((state) => setActiveGateway(state.gateway))
      .catch(() => setActiveGateway("geniuspay"));
  }, []);

  // ── Vérifier si la compagnie a activé "Payer en gare" ──
  useEffect(() => {
    if (!trip?.companyId) return;
    void getPayAtStationConfigSupabase(trip.companyId)
      .then((cfg) => setIsStationMode(cfg.payAtStation))
      .catch(() => setIsStationMode(false));
  }, [trip?.companyId]);

  // ── Charger le message du reçu si mode station ──
  useEffect(() => {
    if (!isStationMode) return;
    void getPayAtStationReceiptMsgSupabase()
      .then(setReceiptMsg)
      .catch(() => setReceiptMsg(DEFAULT_STATION_RECEIPT_MSG));
  }, [isStationMode]);

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

  // ── Calcul du montant selon le mode ──
  useEffect(() => {
    if (!trip?.companyId || !paymentCountryId || checkoutNetwork === "unknown") {
      setPaymentBreakdown(null);
      setStationFee(null);
      setPaymentPreviewError(null);
      return;
    }

    let cancelled = false;
    setPaymentPreviewLoading(true);
    setStationFeeLoading(true);
    setPaymentPreviewError(null);

    if (isStationMode) {
      // Mode gare : calculer uniquement les frais (X+Y+Z+F)
      calculateStationBookingFeeSupabase({
        nominalAmount,
        companyId: trip.companyId,
        countryId: paymentCountryId,
        gateway:   activeGateway,
        method:    "mobile_money",
        network:   checkoutNetwork,
      })
        .then((fee) => {
          if (!cancelled) {
            setStationFee(fee);
            setPaymentBreakdown(null);
          }
        })
        .catch((err) => {
          if (!cancelled) {
            setStationFee(null);
            setPaymentPreviewError(
              err instanceof Error ? err.message : "Calcul des frais impossible",
            );
          }
        })
        .finally(() => {
          if (!cancelled) {
            setPaymentPreviewLoading(false);
            setStationFeeLoading(false);
          }
        });
    } else {
      // Mode normal : paiement complet
      calculateTravelerPaymentSupabase({
        nominalAmount,
        companyId:  trip.companyId,
        countryId:  paymentCountryId,
        gateway:    activeGateway,
        method:     "mobile_money",
        network:    checkoutNetwork,
      })
        .then((breakdown) => {
          if (!cancelled) {
            setPaymentBreakdown(breakdown);
            setStationFee(null);
          }
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
          if (!cancelled) {
            setPaymentPreviewLoading(false);
            setStationFeeLoading(false);
          }
        });
    }

    return () => { cancelled = true; };
  }, [
    trip?.companyId,
    nominalAmount,
    paymentCountryId,
    checkoutNetwork,
    activeGateway,
    isStationMode,
  ]);

  const persistDraft = () => {
    if (!reservationId || !draft) return;
    saveBookingDraft({
      ...draft,
      paymentCountryId,
      paymentNetwork: checkoutNetwork,
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
    if (checkoutNetwork === "unknown") {
      toast.error("Choisissez votre réseau Mobile Money");
      return;
    }
    if (phoneCountryMismatch) {
      toast.error(
        `Le numéro correspond à ${inferredCountryName}, pas à ${paymentCountryName}. Alignez le pays de paiement.`,
      );
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
      const successUrl = `${baseUrl}/${lng}/payment/verify?reservationId=${reservationId}&gateway=${activeGateway}&stationBooking=${isStationMode}`;
      const errorUrl   = `${baseUrl}/${lng}/payment/verify?status=failed&reservationId=${reservationId}&gateway=${activeGateway}`;

      const { checkoutUrl } = await initializePaymentSupabase({
        reservationId,
        passengerName:                   draft.passengerName.trim(),
        passengerPhone:                  phone,
        seatNumber:                      draft.selectedSeat ?? undefined,
        promoId:                         draft.promoId,
        discountAmount:                  draft.discountAmount,
        loyaltyPointsRedeemed:           draft.loyaltyPointsRedeemed,
        loyaltyDiscountAmount:           draft.loyaltyDiscountAmount,
        platformLoyaltyPointsRedeemed:   draft.platformLoyaltyPointsRedeemed,
        platformLoyaltyDiscountAmount:   draft.platformLoyaltyDiscountAmount,
        paymentCountryId,
        paymentNetwork:                  checkoutNetwork,
        successUrl,
        errorUrl,
        // Champs pay-at-station transmis pour que la confirmation génère le bon ticket
        isStationBooking:                isStationMode || undefined,
        stationDueAmount:                isStationMode ? nominalAmount : undefined,
        stationReceiptTitle:             isStationMode ? receiptMsg.title : undefined,
        stationReceiptLine1:             isStationMode ? receiptMsg.line1 : undefined,
        stationReceiptLine2:             isStationMode ? receiptMsg.line2 : undefined,
      });

      window.location.href = checkoutUrl;
    } catch (err) {
      toast.error(supabaseErrorMessage(err, t("errors.generic", { ns: "common" })));
      setPaying(false);
    }
  };

  // ── Montant affiché selon le mode ──
  const displayAmount = isStationMode
    ? (stationFee?.totalOnlineAmount ?? 0)
    : (paymentBreakdown?.totalAmount ?? nominalAmount);

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

      {/* Bandeau "Payer en gare" */}
      {isStationMode && (
        <div className="rounded-xl border border-amber-300 bg-amber-50 dark:bg-amber-950/30 dark:border-amber-700 p-4 space-y-2">
          <div className="flex items-center gap-2 text-amber-800 dark:text-amber-300 font-semibold text-sm">
            <MapPinIcon className="w-4 h-4 shrink-0" />
            Réservation — paiement en gare
          </div>
          <p className="text-sm text-amber-700 dark:text-amber-400 leading-snug">
            {receiptMsg.line1}
          </p>
          <p className="text-sm font-medium text-amber-800 dark:text-amber-300">
            {receiptMsg.line2}{" "}
            <strong>{trip.currency} {nominalAmount.toLocaleString()}</strong> — réglé en gare.
          </p>
          <p className="text-xs text-amber-600 dark:text-amber-500">
            Vous payez maintenant uniquement les frais de service et de traitement.
          </p>
        </div>
      )}

      {/* Notice paiement normal */}
      {!isStationMode && (
        <div className="rounded-xl border p-4 space-y-3 bg-muted/20">
          <div className="flex items-start gap-2">
            <ShieldCheckIcon className="mt-0.5 h-4 w-4 shrink-0 text-amber-600" />
            <p className="text-sm leading-snug">{paymentNotice.infoLine}</p>
          </div>
          <p className="text-sm text-muted-foreground">{paymentNotice.paragraph1}</p>
        </div>
      )}

      <div className="rounded-xl border p-4 space-y-4">
        <div className="space-y-1 text-sm">
          <p><span className="text-muted-foreground">Voyageur :</span> {draft.passengerName}</p>
          <p><span className="text-muted-foreground">Téléphone :</span> {draft.passengerPhone}</p>
          {draft.selectedSeat ? (
            <p><span className="text-muted-foreground">Siège :</span> {draft.selectedSeat}</p>
          ) : null}
        </div>

        <div className="space-y-2">
          <Label htmlFor="payment-country">Pays de paiement *</Label>
          <select
            id="payment-country"
            className="flex h-11 w-full rounded-md border border-input bg-background px-3 py-2 text-sm ring-offset-background focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
            value={paymentCountryId}
            onChange={(event) => selectPaymentCountry(event.target.value)}
            disabled={!paymentCountries?.length}
          >
            <option value="" disabled>
              {paymentCountries ? "Choisissez le pays de votre portefeuille" : "Chargement des pays..."}
            </option>
            {(paymentCountries ?? []).map((country) => (
              <option key={country.id} value={country.id}>
                {country.name}
              </option>
            ))}
          </select>

          {paymentCountries && paymentCountries.length > 0 ? (
            <div className="flex flex-wrap gap-2 pt-1">
              {paymentCountries.map((country) => (
                <button
                  key={country.id}
                  type="button"
                  onClick={() => selectPaymentCountry(country.id)}
                  className={cn(
                    "rounded-full border px-3 py-1 text-xs font-medium transition-colors",
                    paymentCountryId === country.id
                      ? "border-primary bg-primary text-primary-foreground"
                      : "border-input bg-background hover:bg-muted",
                  )}
                >
                  {country.name}
                </button>
              ))}
            </div>
          ) : null}

          {countriesError ? (
            <p className="text-xs text-destructive">{countriesError}</p>
          ) : !paymentCountries ? (
            <p className="text-xs text-muted-foreground">Chargement des pays...</p>
          ) : paymentCountries.length === 0 ? (
            <p className="text-xs text-destructive">Aucun pays de paiement configuré.</p>
          ) : (
            <p className="text-xs text-muted-foreground">
              Sélectionnez le pays où est enregistré votre compte Mobile Money.
            </p>
          )}
        </div>

        <div className="space-y-2">
          <Label>Réseau Mobile Money *</Label>
          {!paymentCountryId || networksLoading ? (
            <p className="text-sm text-muted-foreground py-2">
              {!paymentCountryId ? "Choisissez d'abord un pays" : "Chargement des réseaux..."}
            </p>
          ) : paymentNetworkOptions.length === 0 ? (
            <p className="text-xs text-destructive">
              Aucun réseau configuré pour {paymentCountryName}.
            </p>
          ) : (
            <div className="flex flex-wrap gap-2">
              {paymentNetworkOptions
                .filter((option) => option.value !== "unknown")
                .map((option) => (
                  <button
                    key={option.value}
                    type="button"
                    onClick={() => selectPaymentNetwork(option.value)}
                    className={cn(
                      "rounded-full border px-3 py-1.5 text-xs font-medium transition-colors",
                      paymentNetwork === option.value
                        ? "border-primary bg-primary text-primary-foreground"
                        : "border-input bg-background hover:bg-muted",
                    )}
                  >
                    {paymentNetworkLabel(option.value, lng ?? "fr")}
                  </button>
                ))}
            </div>
          )}
        </div>

        {isGeniusPayCheckout ? (
          <p className="text-xs text-muted-foreground leading-relaxed">
            Paiement via GeniusPay — opérateur{" "}
            {checkoutNetwork !== "unknown"
              ? paymentNetworkLabel(checkoutNetwork, lng ?? "fr")
              : "à choisir"}
            {isStationMode && stationFee
              ? ` · frais ${stationFee.totalOnlineAmount.toLocaleString()} ${trip.currency}`
              : paymentBreakdown
                ? ` · total ${paymentBreakdown.totalAmount.toLocaleString()} ${trip.currency}`
                : ""}
            . Vous finalisez sur la page GeniusPay (geniuspay.ci).
          </p>
        ) : null}

        {phoneCountryMismatch ? (
          <p className="text-xs text-amber-700">
            Ce numéro ({draft.passengerPhone}) correspond plutôt à {inferredCountryName}.
            Vérifiez le pays de paiement.
          </p>
        ) : null}

        {/* Récapitulatif montant */}
        <div className="rounded-lg border bg-background p-3 flex items-center justify-between">
          <div>
            <p className="text-xs font-medium text-muted-foreground">
              {isStationMode ? "Frais à payer maintenant" : "Total à payer"}
            </p>
            <p className="text-2xl font-black text-primary">
              {paymentPreviewLoading || stationFeeLoading
                ? "..."
                : `${trip.currency} ${displayAmount.toLocaleString()}`}
            </p>
            {isStationMode && stationFee ? (
              <p className="text-[11px] text-muted-foreground mt-1">
                Frais plateforme + gateway uniquement · Billet{" "}
                {trip.currency} {nominalAmount.toLocaleString()} réglé en gare
              </p>
            ) : paymentBreakdown ? (
              <p className="text-[11px] text-muted-foreground mt-1">
                Billet {nominalAmount.toLocaleString()} {trip.currency}
                {paymentBreakdown.platformMarginPercent > 0
                  ? ` · plateforme ${paymentBreakdown.platformMarginPercent} %`
                  : ""}
                {paymentBreakdown.geniusPayFeePercent > 0
                  ? ` · GeniusPay ${paymentBreakdown.geniusPayFeePercent} %`
                  : ""}
                {paymentBreakdown.fixedFee > 0
                  ? ` · fixe ${paymentBreakdown.fixedFee.toLocaleString()} ${trip.currency}`
                  : ""}
                {paymentBreakdown.gatewayFeePercent > 0
                  ? ` · réseau ${paymentBreakdown.gatewayFeePercent} %`
                  : ""}
              </p>
            ) : null}
          </div>
          <CreditCardIcon className="w-8 h-8 text-muted-foreground/40" />
        </div>

        {paymentPreviewError ? (
          <p className="text-xs text-amber-700">
            {paymentPreviewError.includes("Configuration frais gateway")
              ? "Frais non configurés pour ce pays — contactez le support."
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
          disabled={
            paying ||
            paymentPreviewLoading ||
            stationFeeLoading ||
            !paymentCountryId ||
            checkoutNetwork === "unknown" ||
            Boolean(phoneCountryMismatch)
          }
        >
          {paying ? (
            <>
              <Loader2Icon className="w-4 h-4 animate-spin" />
              Redirection...
            </>
          ) : (
            <>
              {isStationMode ? "Payer les frais et réserver" : "Payer maintenant"}
              <ArrowRightIcon className="w-4 h-4" />
            </>
          )}
        </Button>
      </div>
      {payDisabledReason && !paying ? (
        <p className="text-xs text-center text-muted-foreground">{payDisabledReason}</p>
      ) : null}
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
