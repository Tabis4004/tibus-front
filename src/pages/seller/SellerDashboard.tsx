import { useState, useEffect, useRef, useCallback } from "react";
import { useQuery, useMutation } from "convex/react";
import { api } from "@/convex/_generated/api.js";
import type { Id } from "@/convex/_generated/dataModel.d.ts";
import { useParams } from "react-router-dom";
import { useTranslation } from "react-i18next";
import { useDebounce } from "@/hooks/use-debounce.ts";
import QRCode from "qrcode";
import { toPng } from "html-to-image";
import { printer } from "@/lib/printer.ts";
import { generateReceiptPDF, type ReceiptFormat, type ReceiptData } from "@/lib/receipt-pdf.ts";
import SeatPicker from "@/components/seat-picker.tsx";
import {
  TicketIcon,
  BusIcon,
  ClockIcon,
  CalendarIcon,
  PlusIcon,
  CheckCircleIcon,
  ListIcon,
  UsersIcon,
  DownloadIcon,
  ShareIcon,
  ArrowLeftIcon,
  PrinterIcon,
  PackageIcon,
  AlertTriangleIcon,
  SearchIcon,
  UserPlusIcon,
  UserIcon,
  StarIcon,
  FileTextIcon,
} from "lucide-react";
import { Button } from "@/components/ui/button.tsx";
import { Input } from "@/components/ui/input.tsx";
import { Label } from "@/components/ui/label.tsx";
import { Badge } from "@/components/ui/badge.tsx";
import { Skeleton } from "@/components/ui/skeleton.tsx";
import { Separator } from "@/components/ui/separator.tsx";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs.tsx";
import { Card, CardContent } from "@/components/ui/card.tsx";
import { Empty, EmptyHeader, EmptyMedia, EmptyTitle, EmptyDescription } from "@/components/ui/empty.tsx";
import { toast } from "sonner";
import { ConvexError } from "convex/values";
import { format, parseISO } from "date-fns";
import { Authenticated, Unauthenticated, AuthLoading } from "@/components/auth/AuthBoundary.tsx";
import { SignInButton } from "@/components/ui/signin.tsx";

function fmt(iso: string, pattern: string) {
  try { return format(parseISO(iso), pattern); } catch { return iso; }
}

const STATUS_STYLE_CLASSES: Record<string, string> = {
  confirmed: "bg-green-500/10 text-green-600 border-green-500/30",
  pending_payment: "bg-yellow-500/10 text-yellow-600 border-yellow-500/30",
  cancelled: "bg-red-500/10 text-red-600 border-red-500/30",
  collected: "bg-blue-500/10 text-blue-600 border-blue-500/30",
};

type Trip = {
  _id: Id<"trips">;
  companyId: Id<"companies">;
  originLoc?: { city: string } | null;
  destLoc?: { city: string } | null;
  origin?: { name: string } | null;
  destination?: { name: string } | null;
  departureTime: string;
  arrivalTime: string;
  priceAmount: number;
  currency: string;
  seatsAvailable: number;
  totalSeats: number;
  bus?: { name: string; busType: string; plateNumber: string; capacity: number } | null;
};

type ParcelData = {
  count: number;
  weight: number;
  amount: number;
};

type SelectedTraveler = {
  _id: Id<"users">;
  name: string;
  phone: string;
};

type CompanyInfo = {
  name: string;
  phone?: string;
  email?: string;
  address?: string;
  nif?: string;
  rccm?: string;
  tva?: string;
  bankAccount?: string;
  logoUrl?: string | null;
  logoStorageId?: string | null;
};

/* ─── Traveler Autocomplete Component ─── */
function TravelerAutocomplete({ onSelect, onQuickCreate }: {
  onSelect: (traveler: SelectedTraveler) => void;
  onQuickCreate: () => void;
}) {
  const { t } = useTranslation("seller");
  const [searchInput, setSearchInput] = useState("");
  const [debouncedSearch] = useDebounce(searchInput, 300);
  const [isOpen, setIsOpen] = useState(false);
  const wrapperRef = useRef<HTMLDivElement>(null);

  const searchResults = useQuery(
    api.sellerTickets.searchTravelers,
    debouncedSearch.length >= 2 ? { searchTerm: debouncedSearch } : "skip"
  );

  // Close dropdown when clicking outside
  useEffect(() => {
    const handleClickOutside = (e: MouseEvent) => {
      if (wrapperRef.current && !wrapperRef.current.contains(e.target as Node)) {
        setIsOpen(false);
      }
    };
    document.addEventListener("mousedown", handleClickOutside);
    return () => document.removeEventListener("mousedown", handleClickOutside);
  }, []);

  const showDropdown = isOpen && debouncedSearch.length >= 2;

  return (
    <div ref={wrapperRef} className="relative">
      <div className="relative">
        <SearchIcon className="absolute left-2.5 top-1/2 -translate-y-1/2 w-4 h-4 text-muted-foreground" />
        <Input
          placeholder={t("search_traveler", { defaultValue: "Rechercher par nom ou telephone..." })}
          value={searchInput}
          onChange={(e) => { setSearchInput(e.target.value); setIsOpen(true); }}
          onFocus={() => setIsOpen(true)}
          className="pl-9"
          autoComplete="off"
        />
      </div>

      {showDropdown && (
        <div className="absolute z-50 top-full left-0 right-0 mt-1 bg-popover border rounded-lg shadow-lg max-h-60 overflow-y-auto">
          {searchResults === undefined ? (
            <div className="px-3 py-2 text-xs text-muted-foreground">
              {t("searching", { defaultValue: "Recherche..." })}
            </div>
          ) : searchResults.length === 0 ? (
            <div className="p-2 space-y-1">
              <p className="text-xs text-muted-foreground px-2 py-1">
                {t("no_traveler_found", { defaultValue: "Aucun voyageur trouvé" })}
              </p>
              <button
                type="button"
                onClick={() => { setIsOpen(false); onQuickCreate(); }}
                className="flex items-center gap-2 w-full px-2 py-2 rounded-md text-sm text-primary font-medium hover:bg-accent cursor-pointer"
              >
                <UserPlusIcon className="w-4 h-4" />
                {t("quick_create_traveler", { defaultValue: "Créer un nouveau voyageur" })}
              </button>
            </div>
          ) : (
            <div className="p-1">
              {searchResults.map((traveler) => (
                <button
                  key={traveler._id}
                  type="button"
                  onClick={() => {
                    onSelect({ _id: traveler._id as Id<"users">, name: traveler.name, phone: traveler.phone });
                    setSearchInput("");
                    setIsOpen(false);
                  }}
                  className="flex items-center gap-2.5 w-full px-2 py-2 rounded-md text-left hover:bg-accent cursor-pointer"
                >
                  <div className="w-7 h-7 rounded-full bg-muted flex items-center justify-center shrink-0">
                    <UserIcon className="w-3.5 h-3.5 text-muted-foreground" />
                  </div>
                  <div className="flex-1 min-w-0">
                    <p className="text-sm font-medium truncate">{traveler.name || "—"}</p>
                    <p className="text-xs text-muted-foreground truncate">{traveler.phone || "—"}</p>
                  </div>
                  {traveler.isCompanyClient && (
                    <StarIcon className="w-3.5 h-3.5 text-yellow-500 shrink-0" />
                  )}
                </button>
              ))}
              <Separator className="my-1" />
              <button
                type="button"
                onClick={() => { setIsOpen(false); onQuickCreate(); }}
                className="flex items-center gap-2 w-full px-2 py-2 rounded-md text-sm text-primary font-medium hover:bg-accent cursor-pointer"
              >
                <UserPlusIcon className="w-4 h-4" />
                {t("quick_create_traveler", { defaultValue: "Créer un nouveau voyageur" })}
              </button>
            </div>
          )}
        </div>
      )}
    </div>
  );
}

/* ─── Quick Create Form ─── */
function QuickCreateForm({ onCreated, onCancel }: {
  onCreated: (traveler: SelectedTraveler) => void;
  onCancel: () => void;
}) {
  const { t } = useTranslation("seller");
  const [name, setName] = useState("");
  const [phone, setPhone] = useState("");
  const [saving, setSaving] = useState(false);
  const quickCreate = useMutation(api.sellerTickets.quickCreateTraveler);

  const handleCreate = async () => {
    if (!name.trim()) { toast.error(t("name_required", { defaultValue: "Nom requis" })); return; }
    if (!phone.trim()) { toast.error(t("phone_required", { defaultValue: "Téléphone requis" })); return; }
    setSaving(true);
    try {
      const result = await quickCreate({ name: name.trim(), phone: phone.trim() });
      toast.success(t("traveler_created", { defaultValue: "Voyageur créé avec succès" }));
      onCreated({ _id: result._id as Id<"users">, name: result.name, phone: result.phone });
    } catch (err) {
      if (err instanceof ConvexError) { toast.error((err.data as { message: string }).message); }
      else { toast.error(t("traveler_create_error", { defaultValue: "Erreur lors de la création" })); }
    } finally { setSaving(false); }
  };

  return (
    <div className="rounded-lg border border-primary/30 bg-primary/5 p-3 space-y-3">
      <div className="flex items-center justify-between">
        <span className="text-xs font-semibold flex items-center gap-1.5">
          <UserPlusIcon className="w-3.5 h-3.5" /> {t("new_traveler", { defaultValue: "Nouveau voyageur" })}
        </span>
        <button type="button" onClick={onCancel} className="text-xs text-muted-foreground cursor-pointer">
          {t("cancel", { ns: "common", defaultValue: "Annuler" })}
        </button>
      </div>
      <div className="space-y-2">
        <div className="space-y-0.5">
          <Label className="text-[10px]">{t("full_name", { defaultValue: "Nom complet" })} *</Label>
          <Input placeholder="John Smith" value={name} onChange={(e) => setName(e.target.value)} className="h-8 text-xs" autoFocus />
        </div>
        <div className="space-y-0.5">
          <Label className="text-[10px]">{t("phone_label", { defaultValue: "Téléphone" })} *</Label>
          <Input placeholder="+237 6xx xxx xxx" value={phone} onChange={(e) => setPhone(e.target.value)} className="h-8 text-xs" />
        </div>
      </div>
      <Button size="sm" className="w-full cursor-pointer text-xs" onClick={handleCreate} disabled={saving}>
        {saving ? t("processing", { ns: "common", defaultValue: "..." }) : t("create_and_select", { defaultValue: "Créer et sélectionner" })}
      </Button>
    </div>
  );
}

/** Data needed to reprint an existing ticket */
type ReprintBooking = {
  bookingReference: string;
  passengerName: string;
  passengerPhone?: string;
  seatNumber?: string;
  totalPrice: number;
  parcelCount?: number;
  parcelWeight?: number;
  parcelAmount?: number;
  trip: {
    departureTime: string;
    arrivalTime: string;
    priceAmount: number;
    currency: string;
    originLoc?: { city: string } | null;
    destLoc?: { city: string } | null;
    origin?: { name: string } | null;
    destination?: { name: string } | null;
    bus?: { name: string; busType: string; plateNumber: string } | null;
  };
};

/** View state for the seller page */
type SellerView =
  | { kind: "dashboard" }
  | { kind: "sell"; trip: Trip }
  | { kind: "receipt"; trip: Trip; ref: string; passengerName: string; passengerPhone: string; parcel: ParcelData | null; totalPrice: number; seatNumber: string | null }
  | { kind: "reprint"; booking: ReprintBooking };

/** Download receipt as a PNG image */
async function downloadReceiptImage(receiptRef: React.RefObject<HTMLDivElement | null>, ref: string) {
  const node = receiptRef.current;
  if (!node) return;
  try {
    const dataUrl = await toPng(node, { cacheBust: true, backgroundColor: "#ffffff", pixelRatio: 2 });
    const link = document.createElement("a");
    link.download = `receipt-${ref}.png`;
    link.href = dataUrl;
    link.click();
  } catch {
    toast.error("Could not generate receipt image");
  }
}

/** Share ticket text */
async function shareTicketText(trip: Trip, confirmedRef: string, passengerName: string, lng: string, companyName: string) {
  const text = [
    `Ticket Tibus - ${confirmedRef}`,
    `${companyName}`,
    `${passengerName}`,
    `${trip.originLoc?.city ?? "?"} -> ${trip.destLoc?.city ?? "?"}`,
    `Depart: ${fmt(trip.departureTime, "dd/MM/yyyy HH:mm")}`,
    `${trip.currency} ${trip.priceAmount.toLocaleString()}`,
    "",
    `Verification: ${window.location.origin}/${lng}/verify/${confirmedRef}`,
    "Powered by Tibus",
  ].join("\n");

  if (typeof navigator.share === "function") {
    try { await navigator.share({ title: `Ticket ${confirmedRef}`, text }); return; } catch { /* cancelled */ }
  }
  try { await navigator.clipboard.writeText(text); toast.success("Copied to clipboard"); return; } catch { /* failed */ }
  window.open(`https://wa.me/?text=${encodeURIComponent(text)}`, "_blank");
}

/* ─── Sell Form Page ─── */
function SellFormPage({ trip, companyName, companyInfo, onClose, onSold }: {
  trip: Trip;
  companyName: string;
  companyInfo: CompanyInfo;
  onClose: () => void;
  onSold: (ref: string, name: string, phone: string, parcel: ParcelData | null, totalPrice: number, seatNumber: string | null, includeTva: boolean) => void;
}) {
  const { t } = useTranslation("seller");
  const [passengerName, setPassengerName] = useState("");
  const [passengerPhone, setPassengerPhone] = useState("");
  const [selectedTraveler, setSelectedTraveler] = useState<SelectedTraveler | null>(null);
  const [showQuickCreate, setShowQuickCreate] = useState(false);
  const [showParcels, setShowParcels] = useState(false);
  const [parcelCount, setParcelCount] = useState("");
  const [parcelWeight, setParcelWeight] = useState("");
  const [parcelAmount, setParcelAmount] = useState("");
  const [loading, setLoading] = useState(false);
  const [includeTva, setIncludeTva] = useState(false);
  const sellerCreateBooking = useMutation(api.sellerTickets.sellerCreateBooking);
  const bookings = useQuery(api.sellerTickets.listCompanyBookings, {});
  const [selectedSeat, setSelectedSeat] = useState<string | null>(null);

  // Fetch occupied seats for this trip
  const occupiedSeats = useQuery(api.bookings.getOccupiedSeats, { tripId: trip._id });

  const tvaRate = parseFloat(companyInfo.tva ?? "") || 0;
  const parcelAmt = parseFloat(parcelAmount) || 0;
  const subtotal = trip.priceAmount + parcelAmt;
  const tvaAmount = includeTva && tvaRate > 0 ? Math.round(subtotal * tvaRate / 100) : 0;
  const totalPrice = subtotal + tvaAmount;

  const handleSelectTraveler = (traveler: SelectedTraveler) => {
    setSelectedTraveler(traveler);
    setPassengerName(traveler.name);
    setPassengerPhone(traveler.phone);
    setShowQuickCreate(false);
  };

  const clearSelectedTraveler = () => {
    setSelectedTraveler(null);
    setPassengerName("");
    setPassengerPhone("");
  };

  const handleSell = async () => {
    if (!passengerName.trim()) { toast.error(t("passenger_name_required")); return; }
    setLoading(true);
    try {
      const pCount = parseInt(parcelCount) || undefined;
      const pWeight = parseFloat(parcelWeight) || undefined;
      const pAmount = parcelAmt > 0 ? parcelAmt : undefined;

      const bookingId = await sellerCreateBooking({
        tripId: trip._id,
        passengerName: passengerName.trim(),
        passengerPhone: passengerPhone.trim() || undefined,
        travelerId: selectedTraveler?._id,
        seatNumber: selectedSeat || undefined,
        parcelCount: pCount,
        parcelWeight: pWeight,
        parcelAmount: pAmount,
      });
      const allBookings = bookings ?? [];
      const found = allBookings.find((b) => b._id === bookingId);
      const ref = found?.bookingReference ?? "---";
      toast.success(t("ticket_sold_success"));
      const parcelData = (pCount || pWeight || pAmount) ? { count: pCount ?? 0, weight: pWeight ?? 0, amount: pAmount ?? 0 } : null;
      onSold(ref, passengerName.trim(), passengerPhone.trim(), parcelData, totalPrice, selectedSeat, includeTva);
    } catch (err) {
      if (err instanceof ConvexError) { toast.error((err.data as { message: string }).message); }
      else { toast.error(t("failed_sell")); }
    } finally { setLoading(false); }
  };

  return (
    <div className="max-w-md mx-auto px-3 py-4 space-y-4">
      <button onClick={onClose} className="flex items-center gap-1.5 text-xs text-muted-foreground cursor-pointer">
        <ArrowLeftIcon className="w-4 h-4" /> {t("back_to_dashboard", { defaultValue: "Retour" })}
      </button>

      <div>
        <h2 className="text-lg font-extrabold">{t("sell_ticket")}</h2>
        <p className="text-xs text-muted-foreground">
          {companyName} · {trip.originLoc?.city ?? "?"} → {trip.destLoc?.city ?? "?"} · {fmt(trip.departureTime, "EEE MMM d, HH:mm")}
        </p>
      </div>

      <div className="rounded-lg bg-muted px-3 py-2 text-sm flex items-center justify-between">
        <span className="text-muted-foreground text-xs">{t("seats_available")}</span>
        <span className="font-bold">{trip.seatsAvailable} / {trip.totalSeats}</span>
      </div>

      {/* Traveler selection */}
      <div className="space-y-2">
        <Label className="text-xs font-semibold">{t("passenger_label", { defaultValue: "Passager" })} *</Label>

        {selectedTraveler ? (
          <div className="flex items-center gap-2 rounded-lg border border-primary/30 bg-primary/5 px-3 py-2">
            <div className="w-8 h-8 rounded-full bg-primary/10 flex items-center justify-center shrink-0">
              <UserIcon className="w-4 h-4 text-primary" />
            </div>
            <div className="flex-1 min-w-0">
              <p className="text-sm font-medium truncate">{selectedTraveler.name}</p>
              <p className="text-xs text-muted-foreground truncate">{selectedTraveler.phone}</p>
            </div>
            <button type="button" onClick={clearSelectedTraveler} className="text-xs text-destructive font-medium cursor-pointer">
              {t("change", { defaultValue: "Changer" })}
            </button>
          </div>
        ) : showQuickCreate ? (
          <QuickCreateForm
            onCreated={handleSelectTraveler}
            onCancel={() => setShowQuickCreate(false)}
          />
        ) : (
          <TravelerAutocomplete
            onSelect={handleSelectTraveler}
            onQuickCreate={() => setShowQuickCreate(true)}
          />
        )}
      </div>

      {/* Manual override - shown when no traveler selected and no quick create */}
      {!selectedTraveler && !showQuickCreate && (
        <div className="space-y-2 border-t pt-3">
          <p className="text-[10px] text-muted-foreground uppercase tracking-wider">{t("or_manual_entry", { defaultValue: "Ou saisie manuelle" })}</p>
          <div className="space-y-1">
            <Label htmlFor="pName" className="text-xs">{t("passenger_name", { ns: "traveler" })} *</Label>
            <Input id="pName" placeholder="John Smith" value={passengerName} onChange={(e) => setPassengerName(e.target.value)} />
          </div>
          <div className="space-y-1">
            <Label htmlFor="pPhone" className="text-xs">{t("phone_optional", { ns: "traveler" })}</Label>
            <Input id="pPhone" placeholder="+237 6xx xxx xxx" value={passengerPhone} onChange={(e) => setPassengerPhone(e.target.value)} />
          </div>
        </div>
      )}

      {/* Seat selection */}
      {trip.totalSeats > 0 && (
        <div className="space-y-2 border-t pt-3">
          <Label className="text-xs font-semibold">{t("choose_seat", { defaultValue: "Choisir un siège" })}</Label>
          <SeatPicker
            totalSeats={trip.totalSeats}
            occupiedSeats={occupiedSeats ?? []}
            selectedSeat={selectedSeat}
            onSelect={setSelectedSeat}
            busType={trip.bus?.busType}
          />
        </div>
      )}

      {/* Parcel section */}
      {!showParcels ? (
        <button
          type="button"
          onClick={() => setShowParcels(true)}
          className="flex items-center gap-2 text-xs text-primary font-medium cursor-pointer"
        >
          <PackageIcon className="w-4 h-4" />
          + {t("add_parcels", { defaultValue: "Ajouter des colis" })}
        </button>
      ) : (
        <div className="rounded-lg border p-3 space-y-3 bg-muted/50">
          <div className="flex items-center justify-between">
            <span className="text-xs font-semibold flex items-center gap-1.5">
              <PackageIcon className="w-3.5 h-3.5" /> {t("parcels", { defaultValue: "Colis" })}
            </span>
            <button type="button" onClick={() => { setShowParcels(false); setParcelCount(""); setParcelWeight(""); setParcelAmount(""); }} className="text-xs text-destructive cursor-pointer">
              {t("remove", { defaultValue: "Retirer", ns: "common" })}
            </button>
          </div>
          <div className="grid grid-cols-3 gap-2">
            <div className="space-y-0.5">
              <Label className="text-[10px]">{t("parcel_count", { defaultValue: "Nombre" })}</Label>
              <Input type="number" min="0" placeholder="0" value={parcelCount} onChange={(e) => setParcelCount(e.target.value)} className="h-8 text-xs" />
            </div>
            <div className="space-y-0.5">
              <Label className="text-[10px]">{t("parcel_weight", { defaultValue: "Poids (Kg)" })}</Label>
              <Input type="number" min="0" step="0.1" placeholder="0" value={parcelWeight} onChange={(e) => setParcelWeight(e.target.value)} className="h-8 text-xs" />
            </div>
            <div className="space-y-0.5">
              <Label className="text-[10px]">{t("parcel_price", { defaultValue: "Montant" })}</Label>
              <Input type="number" min="0" placeholder="0" value={parcelAmount} onChange={(e) => setParcelAmount(e.target.value)} className="h-8 text-xs" />
            </div>
          </div>
        </div>
      )}

      <Separator />

      <div className="space-y-1">
        <div className="flex items-center justify-between text-xs text-muted-foreground">
          <span>{t("ticket_price", { defaultValue: "Billet" })}</span>
          <span>{trip.currency} {trip.priceAmount.toLocaleString()}</span>
        </div>
        {parcelAmt > 0 && (
          <div className="flex items-center justify-between text-xs text-muted-foreground">
            <span>{t("parcels", { defaultValue: "Colis" })}</span>
            <span>{trip.currency} {parcelAmt.toLocaleString()}</span>
          </div>
        )}
        {/* TVA checkbox - only shown if company has TVA configured */}
        {tvaRate > 0 && (
          <div className="flex items-center gap-2 pt-1">
            <input
              type="checkbox"
              id="includeTva"
              checked={includeTva}
              onChange={(e) => setIncludeTva(e.target.checked)}
              className="w-4 h-4 rounded border-muted-foreground/30 cursor-pointer accent-primary"
            />
            <label htmlFor="includeTva" className="text-xs cursor-pointer">
              {t("include_tva", { defaultValue: "Appliquer TVA" })} ({tvaRate}%)
            </label>
            {tvaAmount > 0 && (
              <span className="ml-auto text-xs text-muted-foreground">{trip.currency} {tvaAmount.toLocaleString()}</span>
            )}
          </div>
        )}
        <div className="flex items-center justify-between pt-1">
          <span className="text-xs font-semibold">{t("amount_collect")}</span>
          <span className="font-bold text-primary text-lg">{trip.currency} {totalPrice.toLocaleString()}</span>
        </div>
      </div>

      <div className="flex gap-2 pt-2">
        <Button variant="ghost" onClick={onClose} className="flex-1 cursor-pointer text-xs">{t("cancel", { ns: "common" })}</Button>
        <Button onClick={handleSell} disabled={loading} className="flex-1 cursor-pointer">
          {loading ? t("processing", { ns: "common" }) : t("confirm_sale")}
        </Button>
      </div>
    </div>
  );
}

/* ─── Receipt Page ─── */
function ReceiptPage({ trip, confirmedRef, passengerName, passengerPhone, parcel, totalPrice, seatNumber, companyName, companyInfo, boardingMessage, onNewSale, onDone }: {
  trip: Trip;
  confirmedRef: string;
  passengerName: string;
  passengerPhone: string;
  parcel: ParcelData | null;
  totalPrice: number;
  seatNumber: string | null;
  companyName: string;
  companyInfo?: CompanyInfo;
  boardingMessage?: string;
  onNewSale: () => void;
  onDone: () => void;
}) {
  const { t } = useTranslation("seller");
  const { lng } = useParams<{ lng: string }>();
  const receiptRef = useRef<HTMLDivElement>(null);
  const [qrDataUrl, setQrDataUrl] = useState<string | null>(null);

  useEffect(() => {
    const verifyUrl = `${window.location.origin}/${lng ?? "fr"}/verify/${confirmedRef}`;
    QRCode.toDataURL(verifyUrl, { width: 180, margin: 1, color: { dark: "#000000", light: "#ffffff" }, errorCorrectionLevel: "M" })
      .then(setQrDataUrl)
      .catch(() => setQrDataUrl(null));
  }, [confirmedRef, lng]);

  const handleDownload = useCallback(() => { downloadReceiptImage(receiptRef, confirmedRef); }, [confirmedRef]);
  const handleShare = useCallback(() => { shareTicketText(trip, confirmedRef, passengerName, lng ?? "fr", companyName); }, [trip, confirmedRef, passengerName, lng, companyName]);

  const handlePrint = useCallback(async () => {
    const verifyUrl = `${window.location.origin}/${lng ?? "fr"}/verify/${confirmedRef}`;
    const separator = "--------------------------------";
    const lines: { text: string; align?: "left" | "center" | "right"; size?: "small" | "normal" | "large"; bold?: boolean }[] = [
  { text: companyName, align: "center", size: "large", bold: true },
];

if (companyInfo?.address) lines.push({ text: companyInfo.address, align: "center", size: "small" });
if (companyInfo?.phone || companyInfo?.email) {
  const contact = [companyInfo.phone, companyInfo.email].filter(Boolean).join(" | ");
  lines.push({ text: contact, align: "center", size: "small" });
}
if (companyInfo?.nif || companyInfo?.rccm) {
  const fiscal = [companyInfo.nif ? `NIF:${companyInfo.nif}` : "", companyInfo.rccm ? `RCCM:${companyInfo.rccm}` : ""].filter(Boolean).join(" ");
  lines.push({ text: fiscal, align: "center", size: "small" });
}
if (companyInfo?.tva) lines.push({ text: `TVA: ${companyInfo.tva}`, align: "center", size: "small" });
if (companyInfo?.bankAccount) lines.push({ text: `Compte: ${companyInfo.bankAccount}`, align: "center", size: "small" });

lines.push(
  { text: separator },
  { text: `Reference: ${confirmedRef}`, align: "center", size: "large", bold: true },
  { text: separator },
  { text: `Voyageur: ${passengerName}` },
);
if (passengerPhone) lines.push({ text: `Telephone: ${passengerPhone}` });
if (seatNumber) lines.push({ text: `Siege: #${seatNumber}`, bold: true });

lines.push(
  { text: separator },
  { text: `Trajet: ${trip.originLoc?.city ?? "?"} - ${trip.destLoc?.city ?? "?"}`, bold: true },
  { text: `Depart: ${fmt(trip.departureTime, "dd/MM/yyyy HH:mm")}` },
);
if (trip.arrivalTime) lines.push({ text: `Arrivee: ${fmt(trip.arrivalTime, "dd/MM/yyyy HH:mm")}` });
if (trip.bus) lines.push({ text: `Bus: ${trip.bus.name} - ${trip.bus.plateNumber}` });

lines.push(
  { text: separator },
  { text: `Prix ticket: ${trip.currency} ${trip.priceAmount.toLocaleString()}` },
);

if (parcel && parcel.count > 0) {
  lines.push({ text: `Colis: ${parcel.count}` });
  if (parcel.weight > 0) lines.push({ text: `Poids: ${parcel.weight} Kg` });
  if (parcel.amount > 0) lines.push({ text: `Prix colis: ${trip.currency} ${parcel.amount.toLocaleString()}` });
}

if (companyInfo?.tva) {
  const tvaAmount = Math.round(totalPrice * 0.1925); // adapter au taux réel
  lines.push({ text: `TVA: ${trip.currency} ${tvaAmount.toLocaleString()}` });
}

lines.push(
  { text: separator },
  { text: `Total: ${trip.currency} ${totalPrice.toLocaleString()}`, bold: true, size: "large" },
  { text: `Date: ${format(new Date(), "dd/MM/yyyy HH:mm")}`, size: "small" },
);

if (boardingMessage) {
  lines.push({ text: separator }, { text: `! ${boardingMessage}`, size: "small" });
}
lines.push({ text: separator }, { text: "Powered By Tibus", align: "center", size: "small" });

    try {
      if (printer.isNative) {
        const textBlock = lines.map(l => l.text).join('\n');
        const p3 = (window as unknown as Record<string, unknown>).TibusP3 as { printReceipt58?: (title: string, payload: string) => void; printReceipt80?: (title: string, payload: string) => void } | undefined;
        if (p3?.printReceipt58 || p3?.printReceipt80) {
          const payload = JSON.stringify({
            title: companyName,
            text: textBlock,
            qr: verifyUrl,
            score: 999,
            source: 'seller-ui',
          });
          if (p3.printReceipt58) {
            p3.printReceipt58(companyName, payload);
          } else if (p3.printReceipt80) {
            p3.printReceipt80(companyName, payload);
          }
          return;
        }
      }
      // fallback navigateur
      window.print();
    } catch (e) {
      console.error("Print error:", e);
    }
  }, [confirmedRef, lng, passengerName, passengerPhone, trip, parcel, totalPrice, seatNumber, boardingMessage, companyName, companyInfo]);

  /** Thermal print via browser (80mm or 56mm) */
  const handleThermalPrint = useCallback(async (paperWidth: "80mm" | "56mm") => {
  const verifyUrl = `${window.location.origin}/${lng ?? "fr"}/verify/${confirmedRef}`;
  const sep = paperWidth === "56mm" ? "------------------------------" : "----------------------------------------";

  const lines: { text: string; align?: "left" | "center" | "right"; size?: "small" | "normal" | "large"; bold?: boolean }[] = [
    { text: companyName, align: "center", size: "large", bold: true },
  ];
  if (companyInfo?.address) lines.push({ text: companyInfo.address, align: "center", size: "small" });
  if (companyInfo?.phone || companyInfo?.email) {
    const contact = [companyInfo.phone, companyInfo.email].filter(Boolean).join(" | ");
    lines.push({ text: contact, align: "center", size: "small" });
  }
  if (companyInfo?.nif || companyInfo?.rccm) {
    const fiscal = [companyInfo.nif ? `NIF:${companyInfo.nif}` : "", companyInfo.rccm ? `RCCM:${companyInfo.rccm}` : ""].filter(Boolean).join(" ");
    lines.push({ text: fiscal, align: "center", size: "small" });
  }
  if (companyInfo?.tva) lines.push({ text: `TVA: ${companyInfo.tva}`, align: "center", size: "small" });
  if (companyInfo?.bankAccount) lines.push({ text: `Compte: ${companyInfo.bankAccount}`, align: "center", size: "small" });

  lines.push(
    { text: sep },
    { text: "Reference", align: "center", bold: true, size: "small" },
    { text: confirmedRef, align: "center", size: "large", bold: true },
    { text: sep },
    { text: `Voyageur: ${passengerName}` },
  );
  if (passengerPhone) lines.push({ text: `Telephone: ${passengerPhone}` });

  lines.push(
    { text: sep },
    { text: `Trajet: ${trip.originLoc?.city ?? "?"} -> ${trip.destLoc?.city ?? "?"}`, bold: true },
    { text: `Depart: ${fmt(trip.departureTime, "dd/MM/yyyy HH:mm")}` },
  );
  if (trip.bus) lines.push({ text: `Bus: ${trip.bus.name} - ${trip.bus.plateNumber}` });
  if (seatNumber) lines.push({ text: `Siege: #${seatNumber}`, bold: true });

  if (parcel && parcel.count > 0) {
    lines.push({ text: sep });
    lines.push({ text: `Colis: ${parcel.count}` });
    if (parcel.weight > 0) lines.push({ text: `Poids: ${parcel.weight} Kg` });
    if (parcel.amount > 0) lines.push({ text: `Montant colis: ${trip.currency} ${parcel.amount.toLocaleString()}` });
  }

  lines.push(
    { text: sep },
    { text: `Total: ${trip.currency} ${totalPrice.toLocaleString()}`, bold: true, size: "large" },
  );
  if (boardingMessage) lines.push({ text: sep }, { text: `! ${boardingMessage}`, size: "small" });
  lines.push({ text: sep }, { text: "Powered By Tibus", align: "center", size: "small" });

  // 1) Bridge natif (POS P3 / TPE)
  if (printer.isNative) {
    try {
      const textBlock = lines.map(l => l.text).join('\n');
      const p3 = (window as unknown as Record<string, unknown>).TibusP3 as { printReceipt58?: (title: string, payload: string) => void; printReceipt80?: (title: string, payload: string) => void } | undefined;
      if (p3?.printReceipt58 || p3?.printReceipt80) {
        const payload = JSON.stringify({
          title: companyName,
          text: textBlock,
          qr: verifyUrl,
          score: 999,
          source: 'seller-ui',
        });
        if (paperWidth === "80mm" && p3.printReceipt80) {
          p3.printReceipt80(companyName, payload);
        } else if (p3.printReceipt58) {
          p3.printReceipt58(companyName, payload);
        }
        return;
      }
    } catch (e) {
      console.error("Native print error:", e);
    }
  }

  // 2) Fallback navigateur
  const htmlEl = document.documentElement;
  htmlEl.classList.remove("print-80mm", "print-56mm");
  htmlEl.classList.add(paperWidth === "56mm" ? "print-56mm" : "print-80mm");
  window.print();
  setTimeout(() => htmlEl.classList.remove("print-80mm", "print-56mm"), 1000);
  }, [confirmedRef, lng, passengerName, passengerPhone, trip, parcel, totalPrice, seatNumber, boardingMessage, companyName, companyInfo]);

  /** Download corporate receipt PDF (A4/A5) */
  const handleDownloadPDF = useCallback(async (format: ReceiptFormat) => {
    const verifyUrl = `${window.location.origin}/${lng ?? "fr"}/verify/${confirmedRef}`;
    const receiptData: ReceiptData = {
      bookingReference: confirmedRef,
      passengerName,
      passengerPhone: passengerPhone || undefined,
      companyName,
      companyPhone: companyInfo?.phone,
      companyEmail: companyInfo?.email,
      companyAddress: companyInfo?.address,
      companyNif: companyInfo?.nif,
      companyRccm: companyInfo?.rccm,
      companyTva: companyInfo?.tva,
      companyBankAccount: companyInfo?.bankAccount,
      companyLogoUrl: companyInfo?.logoUrl ?? undefined,
      boardingMessage,
      originCity: trip.originLoc?.city ?? "?",
      originStation: trip.origin?.name ?? trip.originLoc?.city ?? "?",
      destCity: trip.destLoc?.city ?? "?",
      destStation: trip.destination?.name ?? trip.destLoc?.city ?? "?",
      departureTime: fmt(trip.departureTime, "dd/MM/yyyy HH:mm"),
      arrivalTime: fmt(trip.arrivalTime, "dd/MM/yyyy HH:mm"),
      busName: trip.bus?.name,
      busPlateNumber: trip.bus?.plateNumber,
      busType: trip.bus?.busType,
      ticketPrice: trip.priceAmount,
      currency: trip.currency,
      parcelCount: parcel?.count,
      parcelWeight: parcel?.weight,
      parcelAmount: parcel?.amount,
      totalPrice,
      issuedAt: fmt(new Date().toISOString(), "dd/MM/yyyy HH:mm"),
      verifyUrl,
    };
    await generateReceiptPDF(receiptData, format);
  }, [confirmedRef, lng, passengerName, passengerPhone, companyName, companyInfo, boardingMessage, trip, parcel, totalPrice]);

  return (
    <div className="max-w-md mx-auto px-3 py-4 space-y-4">
      {/* Success header */}
      <div className="text-center space-y-1 print-hide">
        <div className="w-12 h-12 rounded-full bg-green-500/10 flex items-center justify-center mx-auto">
          <CheckCircleIcon className="w-6 h-6 text-green-500" />
        </div>
        <h2 className="text-lg font-extrabold">{t("ticket_sold")}</h2>
        <p className="text-xs text-muted-foreground">{t("hand_reference")}</p>
      </div>

      {/* Receipt card */}
      <div id="printable-receipt" ref={receiptRef} className="bg-white text-black py-3 rounded-lg border shadow-sm text-center space-y-2">
        {/* Company header with logo & fiscal info */}
        <div className="px-3 pb-2 border-b border-dashed border-black/30 space-y-1">
          {companyInfo?.logoUrl && (
            <img src={companyInfo.logoUrl} alt="Logo" className="h-10 mx-auto object-contain" />
          )}
          <div className="font-bold text-sm">{companyName}</div>
          {(companyInfo?.address || companyInfo?.phone || companyInfo?.email) && (
            <div className="text-[9px] text-gray-500 leading-tight">
              {companyInfo.address && <span>{companyInfo.address}</span>}
              {companyInfo.phone && <span> | {companyInfo.phone}</span>}
              {companyInfo.email && <span> | {companyInfo.email}</span>}
            </div>
          )}
          {(companyInfo?.nif || companyInfo?.rccm || companyInfo?.tva) && (
            <div className="text-[9px] text-gray-500 leading-tight">
              {companyInfo.nif && <span>NIF: {companyInfo.nif}</span>}
              {companyInfo.rccm && <span>{companyInfo.nif ? " | " : ""}RCCM: {companyInfo.rccm}</span>}
              {companyInfo.tva && <span>{(companyInfo.nif || companyInfo.rccm) ? " | " : ""}TVA: {companyInfo.tva}</span>}
            </div>
          )}
          {companyInfo?.bankAccount && (
            <div className="text-[9px] text-gray-500">Compte: {companyInfo.bankAccount}</div>
          )}
        </div>

        <div className="text-[10px] uppercase tracking-widest text-gray-500">{t("booking_reference")}</div>
        <p className="text-2xl font-extrabold tracking-widest" style={{ color: "#5b21b6" }}>{confirmedRef}</p>

        {/* QR Code */}
        {qrDataUrl && (
          <div className="flex flex-col items-center gap-1 pt-1">
            <img src={qrDataUrl} alt="QR" className="w-24 h-24 rounded" />
            <p className="text-[9px] text-gray-500">Scan pour verification</p>
          </div>
        )}

        <div className="space-y-0.5 text-xs text-left px-3 pt-2">
          {/* Passenger */}
          <div className="flex justify-between gap-1">
            <span className="text-gray-600">{t("passenger_name", { ns: "traveler" })}:</span>
            <span className="font-bold text-right">{passengerName}</span>
          </div>
          {passengerPhone && (
            <div className="flex justify-between gap-1">
              <span className="text-gray-600">{t("phone_optional", { ns: "traveler" })}:</span>
              <span className="text-right">{passengerPhone}</span>
            </div>
          )}
          {seatNumber && (
            <div className="flex justify-between gap-1">
              <span className="text-gray-600">{t("seat_label", { defaultValue: "Siège", ns: "common" })}:</span>
              <span className="font-bold text-right">#{seatNumber}</span>
            </div>
          )}

          {/* Route & departure */}
          <div className="flex justify-between gap-1">
            <span className="text-gray-600">{t("route", { defaultValue: "Trajet" })}:</span>
            <span className="font-bold text-right">{trip.originLoc?.city ?? "?"} → {trip.destLoc?.city ?? "?"}</span>
          </div>
          <div className="flex justify-between gap-1">
            <span className="text-gray-600">{t("departure_label", { defaultValue: "Depart" })}:</span>
            <span className="font-bold text-right">{fmt(trip.departureTime, "dd/MM/yyyy HH:mm")}</span>
          </div>

          {/* Bus info */}
          {trip.bus && (
            <div className="flex justify-between gap-1">
              <span className="text-gray-600">Bus:</span>
              <span className="text-right">{trip.bus.name} · {trip.bus.plateNumber}</span>
            </div>
          )}

          {/* Seat number */}
          {seatNumber && (
            <div className="flex justify-between gap-1">
              <span className="text-gray-600">{t("seat_label", { defaultValue: "Siège" })}:</span>
              <span className="font-bold text-right">#{seatNumber}</span>
            </div>
          )}

          {/* Parcels */}
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
                  <span className="text-right">{trip.currency} {parcel.amount.toLocaleString()}</span>
                </div>
              )}
            </>
          )}

          {/* Total */}
          <div className="flex justify-between gap-1 border-t border-dashed border-black/20 pt-0.5 mt-0.5">
            <span className="text-gray-600 font-bold">Total:</span>
            <span className="font-bold text-right">{trip.currency} {totalPrice.toLocaleString()}</span>
          </div>
        </div>

        {/* Boarding warning message */}
        {boardingMessage && (
          <div className="mx-3 mt-2 px-2 py-1.5 border border-dashed border-black/30 rounded text-[10px] text-left leading-tight">
            <span className="font-bold">!</span> {boardingMessage}
          </div>
        )}

        <div className="border-t border-dashed border-black/30 pt-2 mt-2 text-[9px] font-bold tracking-wider">
          Powered By Tibus
        </div>
      </div>

      {/* Action buttons */}
      <div className="space-y-2 print-hide">
        {/* Thermal POS Printing */}
        <div className="rounded-lg border p-3 space-y-2">
          <p className="text-[10px] uppercase tracking-wider font-semibold text-muted-foreground flex items-center gap-1.5">
            <PrinterIcon className="w-3.5 h-3.5" /> {t("thermal_print", { defaultValue: "Impression Thermique (POS)" })}
          </p>
          <div className="flex gap-2">
            <Button variant="secondary" size="sm" className="flex-1 cursor-pointer text-xs" onClick={handlePrint}>
              <PrinterIcon className="w-3.5 h-3.5 mr-1" />
              {printer.isNative ? "POS" : t("print", { defaultValue: "Imprimer" })}
            </Button>
            <Button variant="secondary" size="sm" className="flex-1 cursor-pointer text-xs" onClick={() => handleThermalPrint("80mm")}>
              80mm
            </Button>
            <Button variant="secondary" size="sm" className="flex-1 cursor-pointer text-xs" onClick={() => handleThermalPrint("56mm")}>
              56mm
            </Button>
          </div>
        </div>

        {/* Corporate PDF Download */}
        <div className="rounded-lg border p-3 space-y-2">
          <p className="text-[10px] uppercase tracking-wider font-semibold text-muted-foreground flex items-center gap-1.5">
            <FileTextIcon className="w-3.5 h-3.5" /> {t("corporate_receipt", { defaultValue: "Recu Corporate (PDF)" })}
          </p>
          <div className="flex gap-2">
            <Button variant="secondary" size="sm" className="flex-1 cursor-pointer text-xs" onClick={() => handleDownloadPDF("a4")}>
              <DownloadIcon className="w-3.5 h-3.5 mr-1" /> A4
            </Button>
            <Button variant="secondary" size="sm" className="flex-1 cursor-pointer text-xs" onClick={() => handleDownloadPDF("a5")}>
              <DownloadIcon className="w-3.5 h-3.5 mr-1" /> A5
            </Button>
          </div>
        </div>

        {/* Quick actions: share, image download */}
        <div className="flex gap-2">
          <Button variant="secondary" size="sm" className="flex-1 cursor-pointer text-xs" onClick={handleDownload}>
            <DownloadIcon className="w-3.5 h-3.5 mr-1.5" />
            PNG
          </Button>
          <Button variant="secondary" size="sm" className="flex-1 cursor-pointer text-xs" onClick={handleShare}>
            <ShareIcon className="w-3.5 h-3.5 mr-1.5" />
            {t("share", { defaultValue: "Partager" })}
          </Button>
        </div>
      </div>
      <div className="space-y-2 print-hide">
        <Button onClick={onNewSale} className="w-full cursor-pointer">
          <PlusIcon className="w-4 h-4 mr-1.5" /> {t("sell_ticket")}
        </Button>
        <Button variant="ghost" onClick={onDone} className="w-full cursor-pointer text-xs">
          {t("done", { ns: "common" })}
        </Button>
      </div>
    </div>
  );
}

/* ─── Main Inner ─── */
function SellerDashboardInner() {
  const { t } = useTranslation("seller");
  const profile = useQuery(api.sellerTickets.getSellerProfile, {});
  const trips = useQuery(api.sellerTickets.listSellerTrips, {});
  const soldTickets = useQuery(api.sellerTickets.listSellerSoldTickets, {});
  const companyBookings = useQuery(api.sellerTickets.listCompanyBookings, {});
  const markCollected = useMutation(api.sellerTickets.markTicketCollected);

  const [view, setView] = useState<SellerView>({ kind: "dashboard" });
  const [collectingId, setCollectingId] = useState<Id<"bookings"> | null>(null);

  const handleCollect = async (bookingId: Id<"bookings">) => {
    setCollectingId(bookingId);
    try {
      await markCollected({ bookingId });
      toast.success(t("marked_collected_success"));
    } catch (err) {
      if (err instanceof ConvexError) { toast.error((err.data as { message: string }).message); }
      else { toast.error(t("failed_update")); }
    } finally { setCollectingId(null); }
  };

  if (profile === undefined || trips === undefined) {
    return (
      <div className="space-y-3">
        {Array.from({ length: 3 }).map((_, i) => (
          <Skeleton key={i} className="h-24 w-full rounded-xl" />
        ))}
      </div>
    );
  }

  if (!profile) {
    return (
      <div className="rounded-xl border p-8 text-center text-muted-foreground space-y-2">
        <TicketIcon className="w-10 h-10 mx-auto opacity-30" />
        <p className="font-medium">{t("access_denied")}</p>
        <p className="text-sm">{t("access_denied_desc")}</p>
      </div>
    );
  }

  const companyName = profile.company?.name ?? "Company";
  const boardingMessage = profile.company?.boardingMessage;
  const companyInfo: CompanyInfo = {
    name: profile.company?.name ?? "Company",
    phone: profile.company?.phone ?? undefined,
    email: profile.company?.email ?? undefined,
    address: profile.company?.address ?? undefined,
    nif: profile.company?.nif ?? undefined,
    rccm: profile.company?.rccm ?? undefined,
    tva: profile.company?.tva ?? undefined,
    bankAccount: profile.company?.bankAccount ?? undefined,
    logoUrl: profile.company?.logoUrl ?? null,
    logoStorageId: profile.company?.logoStorageId ?? null,
  };

  // ─── Sell form view ───
  if (view.kind === "sell") {
    return (
      <SellFormPage
        trip={view.trip}
        companyName={companyName}
        companyInfo={companyInfo}
        onClose={() => setView({ kind: "dashboard" })}
        onSold={(ref, name, phone, parcel, total, seat, _includeTva) => setView({ kind: "receipt", trip: view.trip, ref, passengerName: name, passengerPhone: phone, parcel, totalPrice: total, seatNumber: seat })}
      />
    );
  }

  // ─── Receipt view ───
  if (view.kind === "receipt") {
    return (
      <ReceiptPage
        trip={view.trip}
        confirmedRef={view.ref}
        passengerName={view.passengerName}
        passengerPhone={view.passengerPhone}
        parcel={view.parcel}
        totalPrice={view.totalPrice}
        seatNumber={view.seatNumber}
        companyName={companyName}
        companyInfo={companyInfo}
        boardingMessage={boardingMessage}
        onNewSale={() => setView({ kind: "sell", trip: view.trip })}
        onDone={() => setView({ kind: "dashboard" })}
      />
    );
  }

  // ─── Reprint view ───
  if (view.kind === "reprint") {
    const b = view.booking;
    const reprintTrip: Trip = {
      _id: "" as Id<"trips">,
      companyId: "" as Id<"companies">,
      originLoc: b.trip.originLoc,
      destLoc: b.trip.destLoc,
      origin: b.trip.origin,
      destination: b.trip.destination,
      departureTime: b.trip.departureTime,
      arrivalTime: b.trip.arrivalTime,
      priceAmount: b.trip.priceAmount,
      currency: b.trip.currency,
      seatsAvailable: 0,
      totalSeats: 0,
      bus: b.trip.bus ? { ...b.trip.bus, capacity: 0 } : null,
    };
    const parcel: ParcelData | null = (b.parcelCount && b.parcelCount > 0)
      ? { count: b.parcelCount, weight: b.parcelWeight ?? 0, amount: b.parcelAmount ?? 0 }
      : null;

    return (
      <ReceiptPage
        trip={reprintTrip}
        confirmedRef={b.bookingReference}
        passengerName={b.passengerName}
        passengerPhone={b.passengerPhone ?? ""}
        parcel={parcel}
        totalPrice={b.totalPrice}
        seatNumber={b.seatNumber ?? null}
        companyName={companyName}
        companyInfo={companyInfo}
        boardingMessage={boardingMessage}
        onNewSale={() => setView({ kind: "dashboard" })}
        onDone={() => setView({ kind: "dashboard" })}
      />
    );
  }

  // ─── Dashboard view ───
  return (
    <>
      {/* Company banner */}
      <div className="rounded-xl bg-gradient-to-br from-primary/20 via-primary/10 to-transparent p-4 flex items-center gap-3">
        <div className="w-10 h-10 rounded-xl bg-primary/10 flex items-center justify-center shrink-0">
          <BusIcon className="w-5 h-5 text-primary" />
        </div>
        <div>
          <p className="font-bold">{companyName}</p>
          <p className="text-xs text-muted-foreground">{t("seller_label")} {profile.user.name ?? profile.user.email}</p>
        </div>
        <div className="ml-auto text-right">
          <p className="text-xs text-muted-foreground">{t("sold_today")}</p>
          <p className="font-bold text-lg">
            {soldTickets?.filter((b) => {
              const today = new Date().toISOString().slice(0, 10);
              return b._creationTime ? new Date(b._creationTime).toISOString().slice(0, 10) === today : false;
            }).length ?? 0}
          </p>
        </div>
      </div>

      {/* Boarding message banner */}
      {boardingMessage && (
        <div className="rounded-lg border border-yellow-500/30 bg-yellow-500/5 px-3 py-2 flex items-start gap-2">
          <AlertTriangleIcon className="w-4 h-4 text-yellow-600 shrink-0 mt-0.5" />
          <p className="text-xs text-yellow-700 dark:text-yellow-400">{boardingMessage}</p>
        </div>
      )}

      <Tabs defaultValue="trips">
        <TabsList className="w-full">
          <TabsTrigger value="trips" className="flex-1 cursor-pointer">
            <BusIcon className="w-4 h-4 mr-1.5" /> {t("tab.trips")}
          </TabsTrigger>
          <TabsTrigger value="tickets" className="flex-1 cursor-pointer">
            <TicketIcon className="w-4 h-4 mr-1.5" /> {t("tab.tickets")}
          </TabsTrigger>
          <TabsTrigger value="sold" className="flex-1 cursor-pointer">
            <ListIcon className="w-4 h-4 mr-1.5" /> {t("tab.sales")}
          </TabsTrigger>
        </TabsList>

        {/* ── Trips tab ── */}
        <TabsContent value="trips" className="space-y-3 mt-4">
          {trips.length === 0 ? (
            <Empty>
              <EmptyHeader>
                <EmptyMedia variant="icon"><BusIcon /></EmptyMedia>
                <EmptyTitle>{t("no_trips")}</EmptyTitle>
                <EmptyDescription>{t("no_trips_desc")}</EmptyDescription>
              </EmptyHeader>
            </Empty>
          ) : (
            trips.map((trip) => (
              <Card key={trip._id} className="cursor-default">
                <CardContent className="p-4 space-y-3">
                  <div className="flex items-start justify-between gap-2">
                    <div>
                      <p className="font-bold">
                        {trip.originLoc?.city ?? "?"} → {trip.destLoc?.city ?? "?"}
                      </p>
                      <p className="text-xs text-muted-foreground">
                        {trip.origin?.name} → {trip.destination?.name}
                      </p>
                    </div>
                    <Badge variant={trip.seatsAvailable === 0 ? "destructive" : "secondary"}>
                      {trip.seatsAvailable === 0 ? t("status.full", { ns: "common" }) : `${trip.seatsAvailable} ${t("seats_label")}`}
                    </Badge>
                  </div>

                  <div className="flex items-center gap-4 text-xs text-muted-foreground">
                    <span className="flex items-center gap-1">
                      <CalendarIcon className="w-3.5 h-3.5" />
                      {fmt(trip.departureTime, "EEE, MMM d")}
                    </span>
                    <span className="flex items-center gap-1">
                      <ClockIcon className="w-3.5 h-3.5" />
                      {fmt(trip.departureTime, "HH:mm")} → {fmt(trip.arrivalTime, "HH:mm")}
                    </span>
                    <span className="font-medium text-foreground ml-auto">
                      {trip.currency} {trip.priceAmount.toLocaleString()}
                    </span>
                  </div>

                  {trip.bus && (
                    <div className="text-[10px] text-muted-foreground flex items-center gap-1">
                      <BusIcon className="w-3 h-3" /> {trip.bus.name} · {trip.bus.plateNumber} · {trip.bus.busType}
                    </div>
                  )}

                  <Button
                    size="sm"
                    className="w-full cursor-pointer"
                    disabled={trip.seatsAvailable === 0}
                    onClick={() => setView({ kind: "sell", trip })}
                  >
                    <PlusIcon className="w-4 h-4 mr-1.5" />
                    {t("sell_ticket")}
                  </Button>
                </CardContent>
              </Card>
            ))
          )}
        </TabsContent>

        {/* ── All Company Tickets tab ── */}
        <TabsContent value="tickets" className="space-y-3 mt-4">
          {companyBookings === undefined ? (
            <div className="space-y-3">
              {Array.from({ length: 3 }).map((_, i) => (
                <Skeleton key={i} className="h-24 w-full rounded-xl" />
              ))}
            </div>
          ) : companyBookings.length === 0 ? (
            <Empty>
              <EmptyHeader>
                <EmptyMedia variant="icon"><TicketIcon /></EmptyMedia>
                <EmptyTitle>{t("no_tickets")}</EmptyTitle>
                <EmptyDescription>{t("no_tickets_desc")}</EmptyDescription>
              </EmptyHeader>
            </Empty>
          ) : (
            companyBookings.map((b) => {
              const cls = STATUS_STYLE_CLASSES[b.status] ?? "";
              const statusLabel = t(`status.${b.status}`, { ns: "common", defaultValue: b.status });
              const canCollect = b.status === "confirmed" || b.status === "pending_payment";
              return (
                <div key={b._id} className="rounded-xl border p-4 space-y-2">
                  <div className="flex items-start justify-between gap-2">
                    <div>
                      <p className="font-semibold text-sm">{b.passengerName}</p>
                      <p className="text-xs text-muted-foreground">
                        {b.trip.originLoc?.city ?? "?"} → {b.trip.destLoc?.city ?? "?"}
                      </p>
                    </div>
                    <span className={`inline-flex items-center px-2 py-0.5 rounded-full border text-[10px] font-medium ${cls}`}>
                      {statusLabel}
                    </span>
                  </div>
                  <div className="flex items-center gap-3 text-xs text-muted-foreground">
                    <span className="flex items-center gap-1">
                      <ClockIcon className="w-3.5 h-3.5" />
                      {fmt(b.trip.departureTime, "MMM d, HH:mm")}
                    </span>
                    {b.seatNumber && (
                      <Badge variant="secondary" className="text-[10px]">
                        {t("seat_label", { defaultValue: "Siège", ns: "common" })} #{b.seatNumber}
                      </Badge>
                    )}
                    <code className="bg-muted px-1.5 py-0.5 rounded font-mono ml-auto">{b.bookingReference}</code>
                  </div>
                  <div className="flex items-center justify-between">
                    <span className="text-xs font-semibold text-primary">
                      {b.currency} {b.totalPrice.toLocaleString()}
                    </span>
                    <div className="flex items-center gap-2">
                      <Button size="sm" variant="ghost" className="text-xs h-7 cursor-pointer" onClick={() => setView({
                        kind: "reprint",
                        booking: {
                          bookingReference: b.bookingReference,
                          passengerName: b.passengerName,
                          passengerPhone: b.passengerPhone,
                          seatNumber: b.seatNumber,
                          totalPrice: b.totalPrice,
                          parcelCount: b.parcelCount,
                          parcelWeight: b.parcelWeight,
                          parcelAmount: b.parcelAmount,
                          trip: {
                            departureTime: b.trip.departureTime,
                            arrivalTime: b.trip.arrivalTime,
                            priceAmount: b.trip.priceAmount,
                            currency: b.trip.currency,
                            originLoc: b.trip.originLoc,
                            destLoc: b.trip.destLoc,
                            origin: b.trip.origin,
                            destination: b.trip.destination,
                            bus: b.trip.bus ? { name: b.trip.bus.name, busType: b.trip.bus.busType, plateNumber: b.trip.bus.plateNumber } : null,
                          },
                        },
                      })}>
                        <PrinterIcon className="w-3.5 h-3.5 mr-1" />
                        {t("reprint", { defaultValue: "Reimprimer" })}
                      </Button>
                      {canCollect && (
                        <Button size="sm" variant="secondary" className="text-xs h-7 cursor-pointer" disabled={collectingId === b._id} onClick={() => handleCollect(b._id)}>
                          <CheckCircleIcon className="w-3.5 h-3.5 mr-1" />
                          {collectingId === b._id ? "..." : t("mark_collected")}
                        </Button>
                      )}
                    </div>
                  </div>
                </div>
              );
            })
          )}
        </TabsContent>

        {/* ── My Sales tab ── */}
        <TabsContent value="sold" className="space-y-3 mt-4">
          {soldTickets === undefined ? (
            <div className="space-y-3">
              {Array.from({ length: 3 }).map((_, i) => (
                <Skeleton key={i} className="h-20 w-full rounded-xl" />
              ))}
            </div>
          ) : soldTickets.length === 0 ? (
            <Empty>
              <EmptyHeader>
                <EmptyMedia variant="icon"><UsersIcon /></EmptyMedia>
                <EmptyTitle>{t("no_sales")}</EmptyTitle>
                <EmptyDescription>{t("no_sales_desc")}</EmptyDescription>
              </EmptyHeader>
            </Empty>
          ) : (
            soldTickets.map((b) => {
              const cls = STATUS_STYLE_CLASSES[b.status] ?? "";
              const statusLabel = t(`status.${b.status}`, { ns: "common", defaultValue: b.status });
              return (
                <div key={b._id} className="rounded-xl border p-4 space-y-2">
                  <div className="flex items-start justify-between gap-2">
                    <div>
                      <p className="font-semibold text-sm">{b.passengerName}</p>
                      <p className="text-xs text-muted-foreground">
                        {b.originLoc?.city ?? "?"} → {b.destLoc?.city ?? "?"}
                      </p>
                    </div>
                    <span className={`inline-flex items-center px-2 py-0.5 rounded-full border text-[10px] font-medium ${cls}`}>
                      {statusLabel}
                    </span>
                  </div>
                  <div className="flex items-center justify-between text-xs text-muted-foreground">
                    <code className="bg-muted px-1.5 py-0.5 rounded font-mono">{b.bookingReference}</code>
                    <span className="font-semibold text-foreground">
                      {b.currency} {b.totalPrice.toLocaleString()}
                    </span>
                  </div>
                  <div className="flex justify-end">
                    <Button size="sm" variant="ghost" className="text-xs h-7 cursor-pointer" onClick={() => setView({
                      kind: "reprint",
                      booking: {
                        bookingReference: b.bookingReference,
                        passengerName: b.passengerName,
                        passengerPhone: b.passengerPhone,
                        seatNumber: b.seatNumber,
                        totalPrice: b.totalPrice,
                        parcelCount: b.parcelCount,
                        parcelWeight: b.parcelWeight,
                        parcelAmount: b.parcelAmount,
                        trip: {
                          departureTime: b.trip?.departureTime ?? "",
                          arrivalTime: b.trip?.arrivalTime ?? "",
                          priceAmount: b.trip?.priceAmount ?? 0,
                          currency: b.currency,
                          originLoc: b.originLoc,
                          destLoc: b.destLoc,
                          origin: b.origin,
                          destination: b.destination,
                          bus: b.bus ? { name: b.bus.name, busType: b.bus.busType, plateNumber: b.bus.plateNumber } : null,
                        },
                      },
                    })}>
                      <PrinterIcon className="w-3.5 h-3.5 mr-1" />
                      {t("reprint", { defaultValue: "Reimprimer" })}
                    </Button>
                  </div>
                </div>
              );
            })
          )}
        </TabsContent>
      </Tabs>
    </>
  );
}

export default function SellerDashboard() {
  const { t } = useTranslation("seller");

  return (
    <div className="max-w-2xl mx-auto px-3 py-4 space-y-4">
      <div>
        <h1 className="text-xl font-extrabold tracking-tight">{t("title")}</h1>
        <p className="text-muted-foreground text-xs mt-0.5">{t("desc")}</p>
      </div>

      <AuthLoading>
        <div className="space-y-3">
          {Array.from({ length: 3 }).map((_, i) => (
            <Skeleton key={i} className="h-24 w-full rounded-xl" />
          ))}
        </div>
      </AuthLoading>
      <Authenticated>
        <SellerDashboardInner />
      </Authenticated>
      <Unauthenticated>
        <div className="rounded-xl border p-8 text-center space-y-4">
          <TicketIcon className="w-10 h-10 mx-auto text-muted-foreground opacity-40" />
          <p className="text-sm text-muted-foreground">{t("auth.sign_in_seller", { ns: "common" })}</p>
          <SignInButton />
        </div>
      </Unauthenticated>
    </div>
  );
}
