import { useEffect, useMemo, useState } from "react";
import { useTranslation } from "react-i18next";
import { Link, useParams } from "react-router-dom";
import { format, parseISO } from "date-fns";
import {
  ArrowLeftIcon,
  BookOpenIcon,
  BusIcon,
  CalendarIcon,
  ClockIcon,
  PackageIcon,
  PercentIcon,
  PlusIcon,
  TicketIcon,
  UsersIcon,
  ListIcon,
  ScanLineIcon,
} from "lucide-react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button.tsx";
import { Input } from "@/components/ui/input.tsx";
import { Label } from "@/components/ui/label.tsx";
import { Badge } from "@/components/ui/badge.tsx";
import { Card, CardContent } from "@/components/ui/card.tsx";
import { Skeleton } from "@/components/ui/skeleton.tsx";
import { Separator } from "@/components/ui/separator.tsx";
import SeatPicker from "@/components/seat-picker.tsx";
import ExploreFeaturesButton from "@/components/onboarding/ExploreFeaturesButton.tsx";
import { useAppUser } from "@/hooks/use-app-user.ts";
import { useSupabaseAuth } from "@/components/providers/supabase-auth";
import { useSupabaseOccupiedSeats } from "@/hooks/use-supabase-trip-detail";
import {
  getSellerProfileSupabase,
  getSellerCompanyReceiptInfoSupabase,
  listSellerTripsSupabase,
  sellCounterTicketSupabase,
  type CounterSaleTicket,
  type SellerCompanyReceiptInfo,
  type SellerCounterTrip,
  type SellerProfileSupabase,
} from "@/lib/supabase/seller-counter";
import { getActivePaymentGatewaySupabase } from "@/lib/supabase/payment-gateway.ts";
import { initializePaymentSupabase } from "@/lib/supabase/payments.ts";
import { usePaymentCountryNetworks } from "@/hooks/use-payment-country-networks";
import { calculateTravelerPaymentSupabase } from "@/lib/supabase/payment-fees";
import { supabaseErrorMessage } from "@/lib/supabase/errors";
import { getOpenStationCashSupabase } from "@/lib/supabase/station-cash";
import type { PaymentBreakdown, PaymentGateway, PaymentNetwork } from "@/config/commission.ts";
import { paymentNetworkLabel } from "@/lib/payment-networks.ts";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select.tsx";
import SellerCommissionDashboardPanel from "@/pages/admin/_components/SellerCommissionDashboardPanel.tsx";
import StakeholderPayoutDashboardPanel from "@/pages/admin/_components/StakeholderPayoutDashboardPanel.tsx";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs.tsx";
import CompanySalesLedger from "@/pages/owner/_components/CompanySalesLedger.tsx";
import StationCashPanel from "@/pages/seller/_components/StationCashPanel.tsx";
import { formatTripItineraryLabel } from "@/lib/trip-display.ts";
import ColisAutonomesPage from "@/pages/seller/ColisAutonomesPage.tsx";
import { getCompanyColisSettingsSupabase } from "@/lib/supabase/colis-autonomes.ts";
import SellerTicketReceiptPanel, {
  counterTicketToReceiptInput,
} from "@/components/seller/SellerTicketReceiptPanel.tsx";
import type { TicketReceiptInput } from "@/lib/ticket-receipt-print.ts";
import { useCompanyTicketReprint } from "@/hooks/use-company-ticket-reprint.tsx";
import CompanyLoyaltyUserLookup, {
  type SelectedLoyaltyUser,
} from "@/components/CompanyLoyaltyUserLookup.tsx";
import { hasSellerManualAccess } from "@/lib/seller-manual-access.ts";

type SalePassengerDraft = {
  passengerName: string;
  passengerPhone: string;
  seatNumber: string | null;
  parcelCount: string;
  parcelWeight: string;
  parcelAmount: string;
};

function resizePassengerNames(names: string[], count: number): string[] {
  const next = names.slice(0, count);
  while (next.length < count) next.push("");
  return next;
}

function buildPassengerDrafts(input: {
  passengerCount: number;
  passengerNames: string[];
  passengerPhone: string;
  selectedSeats: string[];
  parcelCount: string;
  parcelWeight: string;
  parcelAmount: string;
}): SalePassengerDraft[] {
  return Array.from({ length: input.passengerCount }, (_, index) => ({
    passengerName: input.passengerNames[index] ?? "",
    passengerPhone: input.passengerPhone,
    seatNumber: input.selectedSeats[index] ?? null,
    parcelCount: index === 0 ? input.parcelCount : "0",
    parcelWeight: index === 0 ? input.parcelWeight : "0",
    parcelAmount: index === 0 ? input.parcelAmount : "0",
  }));
}

function fmt(iso: string, pattern: string) {
  try {
    return format(parseISO(iso), pattern);
  } catch {
    return iso;
  }
}

function toNumber(value: string): number {
  const parsed = Number(value);
  return Number.isFinite(parsed) && parsed > 0 ? parsed : 0;
}

function SaleForm({
  trip,
  profile,
  onBack,
  onSold,
}: {
  trip: SellerCounterTrip;
  profile: SellerProfileSupabase;
  onBack: () => void;
  onSold: (tickets: CounterSaleTicket[]) => void;
}) {
  const { t } = useTranslation("seller");
  const { lng } = useParams<{ lng: string }>();
  const occupiedSeats = useSupabaseOccupiedSeats(trip._id);
  const isDirectSale = profile.canSellDirect;
  const maxPassengers = Math.max(1, Math.min(trip.seatsAvailable, trip.totalSeats || trip.seatsAvailable));
  const [passengerCount, setPassengerCount] = useState(1);
  const [passengerNames, setPassengerNames] = useState<string[]>([""]);
  const [passengerPhone, setPassengerPhone] = useState("");
  const [selectedSeats, setSelectedSeats] = useState<string[]>([]);
  const [parcelCount, setParcelCount] = useState("0");
  const [parcelWeight, setParcelWeight] = useState("0");
  const [parcelAmount, setParcelAmount] = useState("0");
  const [saving, setSaving] = useState(false);
  const [paymentBreakdown, setPaymentBreakdown] = useState<PaymentBreakdown | null>(null);
  const [paymentPreviewLoading, setPaymentPreviewLoading] = useState(false);
  const [paymentPreviewError, setPaymentPreviewError] = useState<string | null>(null);
  const [activeGateway, setActiveGateway] = useState<PaymentGateway>("fedapay");
  const [loyaltyLookupUser, setLoyaltyLookupUser] = useState<SelectedLoyaltyUser | null>(null);
  const [cashOpen, setCashOpen] = useState<boolean | null>(null);
  const [cashPendingReversal, setCashPendingReversal] = useState(false);

  const companyId = trip.companyId ?? profile.company?.id ?? "";

  const {
    countries: paymentCountries,
    paymentCountryId,
    paymentCountryName,
    paymentNetwork,
    paymentNetworkOptions,
    networksLoading,
    selectPaymentCountry,
    selectPaymentNetwork,
  } = usePaymentCountryNetworks({
    activeGateway,
    passengerPhone,
  });

  useEffect(() => {
    if (!isDirectSale) {
      setCashOpen(null);
      setCashPendingReversal(false);
      return;
    }

    let cancelled = false;
    void getOpenStationCashSupabase()
      .then((cash) => {
        if (cancelled) return;
        setCashOpen(cash.open);
        setCashPendingReversal(Boolean(cash.pendingReversal));
      })
      .catch(() => {
        if (!cancelled) setCashOpen(false);
      });

    return () => {
      cancelled = true;
    };
  }, [isDirectSale]);

  useEffect(() => {
    void getActivePaymentGatewaySupabase()
      .then((state) => setActiveGateway(state.gateway))
      .catch(() => setActiveGateway("fedapay"));
  }, []);

  const handlePassengerCountChange = (raw: string) => {
    const parsed = Number.parseInt(raw, 10);
    const nextCount = Number.isFinite(parsed)
      ? Math.min(Math.max(parsed, 1), maxPassengers)
      : 1;
    setPassengerCount(nextCount);
    setPassengerNames((names) => resizePassengerNames(names, nextCount));
    setSelectedSeats((seats) => seats.slice(0, nextCount));
  };

  const actionLabel = isDirectSale ? "Vendre" : t("book_and_pay_online");
  const loadingLabel = isDirectSale ? "Vente..." : "Redirection...";

  const nominalAmount = useMemo(() => {
    const ticketsTotal = trip.priceAmount * passengerCount;
    return ticketsTotal + toNumber(parcelAmount);
  }, [passengerCount, parcelAmount, trip.priceAmount]);

  useEffect(() => {
    if (isDirectSale || !companyId || !paymentCountryId) {
      setPaymentBreakdown(null);
      setPaymentPreviewError(null);
      return;
    }

    let cancelled = false;
    setPaymentPreviewLoading(true);
    setPaymentPreviewError(null);

    calculateTravelerPaymentSupabase({
      nominalAmount,
      companyId,
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
  }, [companyId, isDirectSale, nominalAmount, paymentCountryId, paymentNetwork, activeGateway]);

  const setPassengerName = (index: number, name: string) => {
    setPassengerNames((names) => {
      const next = [...names];
      next[index] = name;
      return next;
    });
  };

  const handleSell = async () => {
    const drafts = buildPassengerDrafts({
      passengerCount,
      passengerNames,
      passengerPhone,
      selectedSeats,
      parcelCount,
      parcelWeight,
      parcelAmount,
    });

    const normalized = drafts.map((traveler) => ({
      ...traveler,
      passengerName: traveler.passengerName.trim(),
      passengerPhone: traveler.passengerPhone.trim(),
    }));

    if (normalized.some((traveler) => !traveler.passengerName)) {
      toast.error("Nom complet requis pour chaque voyageur");
      return;
    }

    if (trip.totalSeats > 0 && selectedSeats.length !== passengerCount) {
      toast.error(`Choisissez ${passengerCount} siège(s) sur le plan`);
      return;
    }

    const uniqueSeats = new Set(selectedSeats);
    if (uniqueSeats.size !== selectedSeats.length) {
      toast.error("Deux voyageurs ne peuvent pas avoir le même siège");
      return;
    }

    const occupied = occupiedSeats ?? [];
    if (selectedSeats.some((seat) => occupied.includes(seat))) {
      toast.error("Un siège sélectionné est déjà occupé");
      return;
    }

    if (!isDirectSale && !passengerPhone.trim()) {
      toast.error("Téléphone requis pour le paiement en ligne");
      return;
    }

    if (!isDirectSale && !paymentCountryId) {
      toast.error("Choisissez le pays de paiement");
      return;
    }

    if (!isDirectSale && (!paymentNetwork || paymentNetwork === "unknown")) {
      toast.error("Choisissez votre réseau Mobile Money");
      return;
    }

    if (isDirectSale && cashOpen === false) {
      toast.error("Ouvrez votre caisse avant toute vente guichet (onglet Guichet → Session caisse journalière)");
      return;
    }

    if (isDirectSale && cashPendingReversal) {
      toast.error("Vente bloquée : un reversement est en attente de validation comptable");
      return;
    }

    setSaving(true);
    try {
      if (!isDirectSale) {
        const baseUrl = window.location.origin;
        const successUrl = `${baseUrl}/${lng ?? "fr"}/payment/verify?reservationId=${trip._id}&source=seller&gateway=${activeGateway}`;
        const errorUrl = `${baseUrl}/${lng ?? "fr"}/payment/verify?status=failed&reservationId=${trip._id}&source=seller&gateway=${activeGateway}`;
        const firstTraveler = normalized[0];

        const { checkoutUrl } = await initializePaymentSupabase({
          reservationId: trip._id,
          passengerName: firstTraveler.passengerName,
          passengerPhone: firstTraveler.passengerPhone,
          seatNumber: firstTraveler.seatNumber ?? undefined,
          travelers: normalized.map((traveler) => ({
            passengerName: traveler.passengerName,
            passengerPhone: traveler.passengerPhone || undefined,
            seatNumber: traveler.seatNumber ?? undefined,
            parcelCount: toNumber(traveler.parcelCount),
            parcelWeight: toNumber(traveler.parcelWeight),
            parcelAmount: toNumber(traveler.parcelAmount),
          })),
          channel: "seller_reservation",
          paymentCountryId,
          paymentNetwork,
          successUrl,
          errorUrl,
        });

        window.location.href = checkoutUrl;
        return;
      }

      const tickets: CounterSaleTicket[] = [];
      for (const traveler of normalized) {
        const ticket = await sellCounterTicketSupabase({
          reservationId: trip._id,
          traveler: {
            passengerName: traveler.passengerName,
            passengerPhone: traveler.passengerPhone || undefined,
            seatNumber: traveler.seatNumber ?? undefined,
            parcelCount: toNumber(traveler.parcelCount),
            parcelWeight: toNumber(traveler.parcelWeight),
            parcelAmount: toNumber(traveler.parcelAmount),
          },
        });
        tickets.push(ticket);
      }

      toast.success(`${tickets.length} ticket(s) vendu(s)`);
      onSold(tickets);
    } catch (err) {
      toast.error(supabaseErrorMessage(err, "Vente impossible"));
    } finally {
      setSaving(false);
    }
  };

  return (
    <div className="space-y-4">
      <button
        type="button"
        onClick={onBack}
        className="flex items-center gap-1.5 text-xs text-muted-foreground cursor-pointer"
      >
        <ArrowLeftIcon className="w-4 h-4" /> Retour
      </button>

      {isDirectSale && cashOpen === false ? (
        <div className="rounded-xl border border-destructive/40 bg-destructive/5 p-4 text-sm text-destructive">
          Ouvrez votre session caisse journalière avant de vendre. Sans caisse ouverte, la vente guichet est refusée par le serveur.
        </div>
      ) : null}
      {isDirectSale && cashPendingReversal ? (
        <div className="rounded-xl border border-amber-500/40 bg-amber-500/5 p-4 text-sm text-amber-700 dark:text-amber-300">
          Reversement en attente : les ventes cash sont suspendues jusqu&apos;à validation comptable.
        </div>
      ) : null}

      <div className="rounded-xl border p-4 space-y-2 bg-muted/20">
        <p className="font-bold">{isDirectSale ? "Vente guichet" : "Réservation tiers"}</p>
        <p className="text-xs text-muted-foreground">
          {profile.company?.name ?? trip.company?.name ?? "Compagnie"} · {trip.originLoc?.city ?? "?"} → {trip.destLoc?.city ?? "?"}
        </p>
        <div className="flex flex-wrap gap-3 text-xs text-muted-foreground">
          <span className="flex items-center gap-1"><CalendarIcon className="w-3.5 h-3.5" />{fmt(trip.departureTime, "dd MMM yyyy")}</span>
          <span className="flex items-center gap-1"><ClockIcon className="w-3.5 h-3.5" />{fmt(trip.departureTime, "HH:mm")}</span>
          <span className="flex items-center gap-1"><UsersIcon className="w-3.5 h-3.5" />{trip.seatsAvailable}/{trip.totalSeats}</span>
        </div>
      </div>

      <Card>
        <CardContent className="p-4 space-y-4">
          <div className="grid gap-3 sm:grid-cols-2">
            <div className="space-y-1.5">
              <Label>Nombre de passagers *</Label>
              <Input
                type="number"
                min={1}
                max={maxPassengers}
                value={passengerCount}
                onChange={(event) => handlePassengerCountChange(event.target.value)}
              />
              <p className="text-[11px] text-muted-foreground">
                {maxPassengers} place(s) disponible(s) sur ce départ
              </p>
            </div>
            <div className="space-y-1.5">
              <Label>Téléphone {isDirectSale ? "" : "*"}</Label>
              {isDirectSale && companyId ? (
                <>
                  <CompanyLoyaltyUserLookup
                    companyId={companyId}
                    query={passengerPhone}
                    onQueryChange={(value) => {
                      setPassengerPhone(value);
                      if (!value.trim()) setLoyaltyLookupUser(null);
                    }}
                    onSelect={(user) => {
                      setLoyaltyLookupUser(user);
                      if (user?.phone) setPassengerPhone(user.phone);
                    }}
                  />
                  {loyaltyLookupUser?.companyLoyaltyActive ? (
                    <p className="text-xs text-primary">
                      Fidélité compagnie : {loyaltyLookupUser.companyPoints} pts pour{" "}
                      {loyaltyLookupUser.displayName}
                    </p>
                  ) : loyaltyLookupUser ? (
                    <p className="text-xs text-muted-foreground">
                      Compte Tibus trouvé — la vente peut continuer. Aucun point fidélité compagnie
                      (programme inactif).
                    </p>
                  ) : null}
                </>
              ) : (
                <Input
                  value={passengerPhone}
                  onChange={(event) => setPassengerPhone(event.target.value)}
                  placeholder="+228..."
                />
              )}
            </div>
          </div>

          <div className="space-y-2">
            <Label>Noms des passagers *</Label>
            <div className="space-y-2">
              {passengerNames.slice(0, passengerCount).map((name, index) => (
                <div key={`passenger-${index}`} className="flex items-center gap-2">
                  <span className="text-xs text-muted-foreground w-16 shrink-0">
                    Passager {index + 1}
                  </span>
                  <Input
                    value={name}
                    onChange={(event) => setPassengerName(index, event.target.value)}
                    placeholder="Nom et prénom"
                    className="flex-1"
                  />
                </div>
              ))}
            </div>
          </div>

          {trip.totalSeats > 0 && (
            <div className="space-y-2">
              <Label>Sièges *</Label>
              <SeatPicker
                totalSeats={trip.totalSeats}
                occupiedSeats={occupiedSeats ?? []}
                selectedSeats={selectedSeats}
                maxSelections={passengerCount}
                onSelectMultiple={setSelectedSeats}
                busType={trip.bus?.busType}
              />
            </div>
          )}

          <div className="rounded-lg border p-3 space-y-3 bg-muted/30">
            <div className="flex items-center gap-1.5 text-xs font-semibold">
              <PackageIcon className="w-3.5 h-3.5" /> Colis (groupé)
            </div>
            <p className="text-[11px] text-muted-foreground">
              Un seul bloc colis pour la vente — rattaché au premier passager.
            </p>
            <div className="grid grid-cols-3 gap-2">
              <div className="space-y-1">
                <Label className="text-[10px]">Nombre</Label>
                <Input
                  type="number"
                  min="0"
                  value={parcelCount}
                  onChange={(event) => setParcelCount(event.target.value)}
                />
              </div>
              <div className="space-y-1">
                <Label className="text-[10px]">Poids (kg)</Label>
                <Input
                  type="number"
                  min="0"
                  step="0.1"
                  value={parcelWeight}
                  onChange={(event) => setParcelWeight(event.target.value)}
                />
              </div>
              <div className="space-y-1">
                <Label className="text-[10px]">Montant</Label>
                <Input
                  type="number"
                  min="0"
                  value={parcelAmount}
                  onChange={(event) => setParcelAmount(event.target.value)}
                />
              </div>
            </div>
          </div>
        </CardContent>
      </Card>

      {!isDirectSale && (
        <>
          <div className="space-y-1.5">
            <Label>Pays de paiement *</Label>
            <Select value={paymentCountryId || undefined} onValueChange={selectPaymentCountry}>
              <SelectTrigger>
                <SelectValue placeholder="Choisissez le pays" />
              </SelectTrigger>
              <SelectContent>
                {(paymentCountries ?? []).map((country) => (
                  <SelectItem key={country.id} value={country.id}>
                    {country.name}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>

          <div className="space-y-1.5">
            <Label>Réseau Mobile Money *</Label>
            <Select
              value={paymentNetwork}
              onValueChange={(value) => selectPaymentNetwork(value as PaymentNetwork)}
              disabled={!paymentCountryId || networksLoading || paymentNetworkOptions.length === 0}
            >
              <SelectTrigger>
                <SelectValue placeholder={paymentCountryId ? "Choisissez le réseau" : "Sélectionnez d'abord un pays"} />
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
            {paymentBreakdown?.usedMaxFallback && (
              <p className="text-xs text-muted-foreground">
                Estimation avec le taux le plus élevé ({paymentBreakdown.network}).
              </p>
            )}
          </div>
        </>
      )}

      <Separator />

      <div className="rounded-xl border p-4 flex items-center justify-between gap-4">
        <div className="space-y-1">
          <p className="text-xs text-muted-foreground">
            {isDirectSale ? "Total guichet" : "Total à payer en ligne"}
          </p>
          {!isDirectSale && (
            <p className="text-xs text-muted-foreground">
              {passengerCount} billet(s) + colis : {trip.currency} {nominalAmount.toLocaleString()}
            </p>
          )}
          <p className="text-xl font-black text-primary">
            {trip.currency}{" "}
            {isDirectSale
              ? nominalAmount.toLocaleString()
              : paymentPreviewLoading
                ? "..."
                : (paymentBreakdown?.totalAmount ?? nominalAmount).toLocaleString()}
          </p>
          {paymentPreviewError && !isDirectSale && (
            <p className="text-xs text-amber-700">
              {paymentPreviewError.includes("Configuration frais gateway")
                ? "Frais de paiement non configurés — le montant affiché est indicatif."
                : paymentPreviewError}
            </p>
          )}
        </div>
        <Button onClick={handleSell} disabled={saving} className="cursor-pointer">
          {saving ? loadingLabel : actionLabel}
        </Button>
      </div>
    </div>
  );
}

export default function SupabaseSellerDashboard() {
  const { t } = useTranslation("seller");
  const { lng } = useParams<{ lng: string }>();
  const { appUserId } = useSupabaseAuth();
  const appUser = useAppUser();
  const [profile, setProfile] = useState<SellerProfileSupabase | null | undefined>(undefined);
  const [trips, setTrips] = useState<SellerCounterTrip[] | undefined>(undefined);
  const [selectedTrip, setSelectedTrip] = useState<SellerCounterTrip | null>(null);
  const [receiptTickets, setReceiptTickets] = useState<CounterSaleTicket[] | null>(null);
  const [companyReceiptInfo, setCompanyReceiptInfo] = useState<SellerCompanyReceiptInfo | null>(null);
  const [colisModuleEnabled, setColisModuleEnabled] = useState(false);
  const companyName = profile?.company?.name ?? companyReceiptInfo?.name ?? "Tibus";
  const { onReprint, reprintView, isReprinting } = useCompanyTicketReprint(
    profile?.company?.id ?? "",
    companyName,
  );

  const load = async () => {
    if (!appUserId) return;
    setProfile(undefined);
    setTrips(undefined);
    try {
      const nextProfile = await getSellerProfileSupabase(appUserId);
      setProfile(nextProfile);
      if (!nextProfile) {
        setTrips([]);
        return;
      }
      const [nextTrips, colisSettings, receiptInfo] = await Promise.all([
        listSellerTripsSupabase(nextProfile),
        nextProfile.company
          ? getCompanyColisSettingsSupabase(nextProfile.company.id).catch(() => null)
          : Promise.resolve(null),
        nextProfile.company
          ? getSellerCompanyReceiptInfoSupabase(nextProfile.company.id).catch(() => null)
          : Promise.resolve(null),
      ]);
      setTrips(nextTrips);
      setColisModuleEnabled(Boolean(colisSettings?.colisAutonomeEnabled));
      setCompanyReceiptInfo(receiptInfo);
    } catch (err) {
      toast.error(supabaseErrorMessage(err, "Chargement vendeur impossible"));
      setProfile(null);
      setTrips([]);
    }
  };

  useEffect(() => {
    void load();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [appUserId]);

  if (appUser.isLoading || profile === undefined || trips === undefined) {
    return (
      <div className="space-y-3">
        {Array.from({ length: 3 }).map((_, index) => (
          <Skeleton key={index} className="h-24 w-full rounded-xl" />
        ))}
      </div>
    );
  }

  if (!profile) {
    return (
      <div className="rounded-xl border p-8 text-center text-muted-foreground space-y-2">
        <TicketIcon className="w-10 h-10 mx-auto opacity-30" />
        <p className="font-medium">Acces vendeur refuse</p>
        <p className="text-sm">Votre compte n'a pas de role vendeur sur une compagnie.</p>
      </div>
    );
  }

  if (isReprinting && reprintView) {
    return reprintView;
  }

  if (selectedTrip && receiptTickets) {
    const companyName = profile.company?.name ?? selectedTrip.company?.name ?? "Tibus";
    return (
      <div className="space-y-6">
        {receiptTickets.length > 1 && (
          <p className="text-center text-xs text-muted-foreground print-hide">
            {receiptTickets.length} tickets emis · impression POS ticket par ticket
          </p>
        )}
        {receiptTickets.map((ticket, index) => (
          <SellerTicketReceiptPanel
            key={ticket.bookingId}
            input={counterTicketToReceiptInput(ticket, selectedTrip, companyName)}
            companyInfo={companyReceiptInfo ?? undefined}
            showSuccessHeader={index === 0}
            onBack={
              index === receiptTickets.length - 1
                ? () => {
                    setReceiptTickets(null);
                    setSelectedTrip(null);
                    void load();
                  }
                : undefined
            }
            onNewSale={
              index === receiptTickets.length - 1
                ? () => {
                    setReceiptTickets(null);
                  }
                : undefined
            }
            onDone={
              index === receiptTickets.length - 1
                ? () => {
                    setReceiptTickets(null);
                    setSelectedTrip(null);
                    void load();
                  }
                : undefined
            }
          />
        ))}
      </div>
    );
  }

  if (selectedTrip) {
    return (
      <SaleForm
        trip={selectedTrip}
        profile={profile}
        onBack={() => setSelectedTrip(null)}
        onSold={(tickets) => {
          setReceiptTickets(tickets);
        }}
      />
    );
  }

  const totalAvailableSeats = trips.reduce((sum, trip) => sum + trip.seatsAvailable, 0);
  const canCancelTickets =
    profile.company &&
    (profile.roleNames.includes("vendeur") ||
      profile.roleNames.includes("chauffeur") ||
      profile.roleNames.includes("owner"));

  const isPlatformSeller = profile.roleNames.some((role) =>
    ["vendeur_independant", "vendeur_master"].includes(role),
  );

  const dashboardCards = [
    {
      label: profile.canSellDirect ? "Mode caisse" : "Mode réservation",
      value: profile.canSellDirect ? "Guichet" : "Tiers",
      icon: TicketIcon,
    },
    {
      label: "Départs",
      value: trips.length.toLocaleString(),
      icon: BusIcon,
    },
    {
      label: "Places",
      value: totalAvailableSeats.toLocaleString(),
      icon: UsersIcon,
    },
  ];

  const counterContent = (
    <div className="space-y-4">
      <div data-tour="seller-header" className="flex items-center justify-between gap-2">
        <p className="text-sm font-bold">Espace guichet</p>
        <div className="flex items-center gap-2">
          {hasSellerManualAccess(appUser.roles) ? (
            <Button variant="outline" size="sm" className="h-8 cursor-pointer" asChild>
              <Link to={`/${lng ?? "fr"}/manual/vendeur`}>
                <BookOpenIcon className="w-4 h-4 mr-1.5" />
                Manuel
              </Link>
            </Button>
          ) : null}
          <ExploreFeaturesButton variant="icon" />
          <Button variant="outline" size="sm" className="h-8 cursor-pointer" asChild>
            <Link to={`/${lng ?? "fr"}/verify/scan`} data-tour="seller-scan">
              <ScanLineIcon className="w-4 h-4 mr-1.5" />
              Scanner
            </Link>
          </Button>
        </div>
      </div>
      <div className="rounded-xl bg-gradient-to-br from-primary/20 via-primary/10 to-transparent p-4 flex items-center gap-3">
        <div className="w-10 h-10 rounded-xl bg-primary/10 flex items-center justify-center shrink-0">
          <BusIcon className="w-5 h-5 text-primary" />
        </div>
        <div className="min-w-0">
          <p className="font-bold truncate">{profile.company?.name ?? "Agent marchand"}</p>
          <p className="text-xs text-muted-foreground truncate">
            {profile.user.name || profile.user.email || "Vendeur"}
          </p>
        </div>
      </div>

      <div data-tour="seller-kpis" className="grid grid-cols-2 md:grid-cols-3 gap-3">
        {dashboardCards.map(({ label, value, icon: Icon }) => (
          <Card key={label}>
            <CardContent className="p-4">
              <div className="w-8 h-8 rounded-lg bg-primary/10 flex items-center justify-center mb-2">
                <Icon className="w-4 h-4 text-primary" />
              </div>
              <p className="text-xs text-muted-foreground">{label}</p>
              <p className="font-black text-lg truncate">{value}</p>
            </CardContent>
          </Card>
        ))}
      </div>

      {isPlatformSeller ? (
        <Card data-tour="seller-commissions">
          <CardContent className="p-4 space-y-6">
            <SellerCommissionDashboardPanel embedded allowPaymentRequest />
            <StakeholderPayoutDashboardPanel embedded />
          </CardContent>
        </Card>
      ) : (
        <Card>
          <CardContent className="p-4">
            <StakeholderPayoutDashboardPanel embedded />
          </CardContent>
        </Card>
      )}

      {profile.canSellDirect && profile.company ? (
        <StationCashPanel
          companyId={profile.company.id}
          canOpen={
            profile.roleNames.includes("vendeur") ||
            profile.roleNames.includes("chauffeur")
          }
        />
      ) : null}

      <div id="third-party-booking" data-tour="seller-departures" className="scroll-mt-20">
        <h2 className="text-sm font-bold uppercase tracking-wider text-muted-foreground">Departs disponibles</h2>
      </div>

      {trips.length === 0 ? (
        <div className="rounded-xl border p-8 text-center text-muted-foreground">
          <BusIcon className="w-10 h-10 mx-auto opacity-30 mb-2" />
          <p className="font-medium">Aucun depart disponible</p>
        </div>
      ) : (
        trips.map((trip, tripIndex) => (
          <Card key={trip._id}>
            <CardContent className="p-4 space-y-3">
              <div className="flex items-start justify-between gap-3">
                <div>
                  <p className="font-bold text-sm leading-snug">
                    {formatTripItineraryLabel({
                      originCity: trip.originLoc?.city ?? "?",
                      originGare: trip.origin?.name ?? "?",
                      destinationCity: trip.destLoc?.city ?? "?",
                      destinationGare: trip.destination?.name ?? "?",
                      departureTime: trip.departureTime,
                      arrivalTime: trip.arrivalTime,
                      priceAmount: trip.priceAmount,
                      currency: trip.currency,
                    })}
                  </p>
                </div>
                <Badge variant={trip.seatsAvailable === 0 ? "destructive" : "secondary"}>
                  {trip.seatsAvailable}/{trip.totalSeats}
                </Badge>
              </div>

              <div className="flex flex-wrap gap-3 text-xs text-muted-foreground">
                <span className="flex items-center gap-1"><CalendarIcon className="w-3.5 h-3.5" />{fmt(trip.departureTime, "dd MMM")}</span>
                <span className="flex items-center gap-1"><ClockIcon className="w-3.5 h-3.5" />{fmt(trip.departureTime, "HH:mm")}</span>
                <span className="font-semibold text-foreground ml-auto">{trip.currency} {trip.priceAmount.toLocaleString()}</span>
              </div>

              {trip.bus && (
                <p className="text-[10px] text-muted-foreground flex items-center gap-1">
                  <BusIcon className="w-3 h-3" /> {trip.bus.name} · {trip.bus.busType}
                </p>
              )}

              <Button
                size="sm"
                className="w-full cursor-pointer"
                disabled={trip.seatsAvailable === 0}
                data-tour={tripIndex === 0 ? "seller-sell-trip" : undefined}
                onClick={() => setSelectedTrip(trip)}
              >
                <PlusIcon className="w-4 h-4 mr-1.5" /> {profile.canSellDirect ? t("counter_sale") : t("third_party_reservation")}
              </Button>
            </CardContent>
          </Card>
        ))
      )}

      <p className="text-[11px] text-muted-foreground">
        {t("counter_sale_note", {
          defaultValue:
            profile.canSellDirect
              ? "Indiquez le nombre de passagers, leurs noms, les sièges sur le plan, puis validez une seule fois."
              : "Indiquez les passagers et le téléphone : le voyageur paie ensuite en ligne.",
        })}
      </p>
    </div>
  );

  if (profile.company) {
    return (
      <Tabs defaultValue="counter">
        <TabsList className="w-full">
          <TabsTrigger value="counter" className="flex-1" data-tour="seller-tab-counter">
            <BusIcon className="w-4 h-4 mr-1.5" />
            Guichet
          </TabsTrigger>
          <TabsTrigger value="sales" className="flex-1" data-tour="seller-tab-sales">
            <ListIcon className="w-4 h-4 mr-1.5" />
            Ventes compagnie
          </TabsTrigger>
          {colisModuleEnabled && profile.canSellDirect ? (
            <TabsTrigger value="colis" className="flex-1" data-tour="seller-colis">
              <PackageIcon className="w-4 h-4 mr-1.5" />
              Colis
            </TabsTrigger>
          ) : null}
        </TabsList>
        <TabsContent value="counter" className="mt-4">
          {counterContent}
        </TabsContent>
        <TabsContent value="sales" className="mt-4">
          <CompanySalesLedger
            companyId={profile.company.id}
            canCancel={Boolean(canCancelTickets)}
            canReprint
            onReprint={onReprint}
          />
        </TabsContent>
        {colisModuleEnabled && profile.canSellDirect ? (
          <TabsContent value="colis" className="mt-4">
            <ColisAutonomesPage />
          </TabsContent>
        ) : null}
      </Tabs>
    );
  }

  return counterContent;
}
