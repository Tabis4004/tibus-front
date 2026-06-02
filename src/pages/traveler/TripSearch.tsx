import { useState, useMemo } from "react";
import { useQuery } from "convex/react";
import { api } from "@/convex/_generated/api.js";
import type { Id } from "@/convex/_generated/dataModel.d.ts";
import { Link, useParams } from "react-router-dom";
import {
  MapPinIcon,
  CalendarIcon,
  ClockIcon,
  BusIcon,
  ArrowRightIcon,
  BuildingIcon,
  GlobeIcon,
  FilterIcon,
  XIcon,
  WalletIcon,
  RouteIcon,
} from "lucide-react";
import { Input } from "@/components/ui/input.tsx";
import { Button } from "@/components/ui/button.tsx";
import { Card, CardContent } from "@/components/ui/card.tsx";
import { Badge } from "@/components/ui/badge.tsx";
import { Skeleton } from "@/components/ui/skeleton.tsx";
import { Separator } from "@/components/ui/separator.tsx";
import {
  Empty,
  EmptyHeader,
  EmptyMedia,
  EmptyTitle,
  EmptyDescription,
} from "@/components/ui/empty.tsx";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select.tsx";
import { format, parseISO } from "date-fns";
import { useTranslation } from "react-i18next";
import { motion } from "motion/react";

function formatTime(iso: string) {
  try {
    return format(parseISO(iso), "HH:mm");
  } catch {
    return iso;
  }
}
function formatDate(iso: string) {
  try {
    return format(parseISO(iso), "EEE, dd MMM yyyy");
  } catch {
    return iso;
  }
}

function getOccupancyPercent(seatsAvailable: number, totalSeats: number): number {
  if (totalSeats === 0) return 100;
  const occupied = totalSeats - seatsAvailable;
  return Math.round((occupied / totalSeats) * 100);
}

function getOccupancyColor(percent: number) {
  if (percent <= 30) return { bar: "bg-emerald-500", text: "text-emerald-600 dark:text-emerald-400", label: "low" };
  if (percent <= 75) return { bar: "bg-amber-500", text: "text-amber-600 dark:text-amber-400", label: "medium" };
  return { bar: "bg-red-500", text: "text-red-600 dark:text-red-400", label: "high" };
}

export default function TripSearch() {
  const { t } = useTranslation("traveler");
  const { lng } = useParams<{ lng: string }>();

  // Filter states
  const [countryId, setCountryId] = useState<string>("all");
  const [companyId, setCompanyId] = useState<string>("all");
  const [originCity, setOriginCity] = useState("");
  const [destinationCity, setDestinationCity] = useState("");
  const [departureDate, setDepartureDate] = useState("");
  const [maxPrice, setMaxPrice] = useState("");
  const [showFilters, setShowFilters] = useState(false);

  // Data sources for filters
  const countries = useQuery(api.geography.listCountries, {});
  const companies = useQuery(api.companies.listActiveCompanies, {});
  const cities = useQuery(
    api.geography.listCities,
    countryId !== "all" ? { countryId: countryId as Id<"countries"> } : {}
  );

  // Build search args
  const searchArgs = useMemo(() => {
    const args: {
      originCity?: string;
      destinationCity?: string;
      departureDate?: string;
      companyId?: Id<"companies">;
      countryId?: Id<"countries">;
    } = {};
    if (originCity.trim()) args.originCity = originCity.trim();
    if (destinationCity.trim()) args.destinationCity = destinationCity.trim();
    if (departureDate) args.departureDate = departureDate;
    if (companyId !== "all") args.companyId = companyId as Id<"companies">;
    if (countryId !== "all") args.countryId = countryId as Id<"countries">;
    return args;
  }, [originCity, destinationCity, departureDate, companyId, countryId]);

  const trips = useQuery(api.bookings.searchTrips, searchArgs);

  // Filter by price on client side
  const filteredTrips = useMemo(() => {
    if (!trips) return undefined;
    if (!maxPrice) return trips;
    const priceLimit = parseFloat(maxPrice);
    if (isNaN(priceLimit)) return trips;
    return trips.filter((trip) => trip.priceAmount <= priceLimit);
  }, [trips, maxPrice]);

  // Get unique city names for autocomplete-like dropdowns
  const cityNames = useMemo(() => {
    if (!cities) return [];
    return [...new Set(cities.map((c) => c.name))].sort();
  }, [cities]);

  const hasActiveFilters =
    countryId !== "all" ||
    companyId !== "all" ||
    originCity !== "" ||
    destinationCity !== "" ||
    departureDate !== "" ||
    maxPrice !== "";

  const clearFilters = () => {
    setCountryId("all");
    setCompanyId("all");
    setOriginCity("");
    setDestinationCity("");
    setDepartureDate("");
    setMaxPrice("");
  };

  return (
    <div className="max-w-6xl mx-auto px-4 py-6 space-y-5">
      {/* Header */}
      <motion.div
        className="flex items-center justify-between"
        initial={{ opacity: 0, y: -10 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ duration: 0.3, ease: "easeOut" }}
      >
        <div>
          <h1 className="text-2xl md:text-3xl font-extrabold tracking-tight">
            {t("search_trips")}
          </h1>
          <p className="text-muted-foreground text-sm mt-0.5">
            {t("search_trips_desc")}
          </p>
        </div>
        {/* Mobile filter toggle */}
        <Button
          variant="ghost"
          size="sm"
          className="cursor-pointer gap-1.5 relative md:hidden"
          onClick={() => setShowFilters(!showFilters)}
        >
          <FilterIcon className="w-4 h-4" />
          {t("labels.filters", { ns: "common", defaultValue: "Filters" })}
          {hasActiveFilters && (
            <span className="absolute -top-1 -right-1 w-2.5 h-2.5 rounded-full bg-primary" />
          )}
        </Button>
      </motion.div>

      {/* Desktop inline filters (always visible on md+) */}
      <div className="hidden md:block rounded-xl border bg-muted/30 p-4">
        <div className="flex items-end gap-3 flex-wrap">
          {/* Country */}
          <div className="space-y-1 min-w-[140px]">
            <label className="text-xs font-medium text-muted-foreground flex items-center gap-1">
              <GlobeIcon className="w-3 h-3" />
              {t("labels.country", { ns: "common", defaultValue: "Country" })}
            </label>
            <Select value={countryId} onValueChange={(v) => { setCountryId(v); setOriginCity(""); setDestinationCity(""); }}>
              <SelectTrigger className="cursor-pointer h-9">
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="all">
                  {t("labels.all_countries", { ns: "common", defaultValue: "All countries" })}
                </SelectItem>
                {countries?.map((c) => (
                  <SelectItem key={c._id} value={c._id}>{c.name}</SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>

          {/* From city */}
          <div className="space-y-1 min-w-[140px]">
            <label className="text-xs font-medium text-muted-foreground flex items-center gap-1">
              <MapPinIcon className="w-3 h-3" />
              {t("from_city")}
            </label>
            {cityNames.length > 0 ? (
              <Select value={originCity || "all"} onValueChange={(v) => setOriginCity(v === "all" ? "" : v)}>
                <SelectTrigger className="cursor-pointer h-9">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="all">
                    {t("labels.any_city", { ns: "common", defaultValue: "Any city" })}
                  </SelectItem>
                  {cityNames.map((name) => (
                    <SelectItem key={name} value={name}>{name}</SelectItem>
                  ))}
                </SelectContent>
              </Select>
            ) : (
              <Input
                placeholder={t("from_city")}
                value={originCity}
                onChange={(e) => setOriginCity(e.target.value)}
                className="h-9"
              />
            )}
          </div>

          {/* To city */}
          <div className="space-y-1 min-w-[140px]">
            <label className="text-xs font-medium text-muted-foreground flex items-center gap-1">
              <MapPinIcon className="w-3 h-3 text-primary" />
              {t("to_city")}
            </label>
            {cityNames.length > 0 ? (
              <Select value={destinationCity || "all"} onValueChange={(v) => setDestinationCity(v === "all" ? "" : v)}>
                <SelectTrigger className="cursor-pointer h-9">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="all">
                    {t("labels.any_city", { ns: "common", defaultValue: "Any city" })}
                  </SelectItem>
                  {cityNames.map((name) => (
                    <SelectItem key={name} value={name}>{name}</SelectItem>
                  ))}
                </SelectContent>
              </Select>
            ) : (
              <Input
                placeholder={t("to_city")}
                value={destinationCity}
                onChange={(e) => setDestinationCity(e.target.value)}
                className="h-9"
              />
            )}
          </div>

          {/* Date */}
          <div className="space-y-1 min-w-[150px]">
            <label className="text-xs font-medium text-muted-foreground flex items-center gap-1">
              <CalendarIcon className="w-3 h-3" />
              {t("labels.date", { ns: "common", defaultValue: "Date" })}
            </label>
            <Input
              type="date"
              value={departureDate}
              onChange={(e) => setDepartureDate(e.target.value)}
              className="h-9"
            />
          </div>

          {/* Company */}
          <div className="space-y-1 min-w-[140px]">
            <label className="text-xs font-medium text-muted-foreground flex items-center gap-1">
              <BuildingIcon className="w-3 h-3" />
              {t("labels.company", { ns: "common", defaultValue: "Company" })}
            </label>
            <Select value={companyId} onValueChange={setCompanyId}>
              <SelectTrigger className="cursor-pointer h-9">
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="all">
                  {t("labels.all_companies", { ns: "common", defaultValue: "All companies" })}
                </SelectItem>
                {companies?.map((c) => (
                  <SelectItem key={c._id} value={c._id}>{c.name}</SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>

          {/* Max Price */}
          <div className="space-y-1 min-w-[120px]">
            <label className="text-xs font-medium text-muted-foreground flex items-center gap-1">
              <WalletIcon className="w-3 h-3" />
              {t("max_price", { defaultValue: "Max price" })}
            </label>
            <Input
              type="number"
              placeholder="10000"
              value={maxPrice}
              onChange={(e) => setMaxPrice(e.target.value)}
              className="h-9"
            />
          </div>

          {/* Clear */}
          {hasActiveFilters && (
            <Button
              variant="ghost"
              size="sm"
              className="cursor-pointer text-xs h-9 gap-1 shrink-0"
              onClick={clearFilters}
            >
              <XIcon className="w-3 h-3" />
              {t("buttons.clear", { ns: "common", defaultValue: "Clear" })}
            </Button>
          )}
        </div>
      </div>

      {/* Mobile filters panel */}
      {showFilters && (
        <div className="md:hidden rounded-xl border bg-muted/30 p-4 space-y-3">
          <div className="flex items-center justify-between">
            <p className="text-sm font-semibold">
              {t("labels.filters", { ns: "common", defaultValue: "Filters" })}
            </p>
            {hasActiveFilters && (
              <Button
                variant="ghost"
                size="sm"
                className="cursor-pointer text-xs h-7 gap-1"
                onClick={clearFilters}
              >
                <XIcon className="w-3 h-3" />
                {t("buttons.clear", { ns: "common", defaultValue: "Clear" })}
              </Button>
            )}
          </div>

          {/* Country filter */}
          <div className="space-y-1">
            <label className="text-xs font-medium text-muted-foreground flex items-center gap-1">
              <GlobeIcon className="w-3 h-3" />
              {t("labels.country", { ns: "common", defaultValue: "Country" })}
            </label>
            <Select value={countryId} onValueChange={(v) => { setCountryId(v); setOriginCity(""); setDestinationCity(""); }}>
              <SelectTrigger className="cursor-pointer">
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="all">
                  {t("labels.all_countries", { ns: "common", defaultValue: "All countries" })}
                </SelectItem>
                {countries?.map((c) => (
                  <SelectItem key={c._id} value={c._id}>{c.name}</SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>

          {/* Company filter */}
          <div className="space-y-1">
            <label className="text-xs font-medium text-muted-foreground flex items-center gap-1">
              <BuildingIcon className="w-3 h-3" />
              {t("labels.company", { ns: "common", defaultValue: "Company" })}
            </label>
            <Select value={companyId} onValueChange={setCompanyId}>
              <SelectTrigger className="cursor-pointer">
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="all">
                  {t("labels.all_companies", { ns: "common", defaultValue: "All companies" })}
                </SelectItem>
                {companies?.map((c) => (
                  <SelectItem key={c._id} value={c._id}>{c.name}</SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>

          {/* City filters */}
          <div className="grid grid-cols-2 gap-3">
            <div className="space-y-1">
              <label className="text-xs font-medium text-muted-foreground flex items-center gap-1">
                <MapPinIcon className="w-3 h-3" />
                {t("from_city")}
              </label>
              {cityNames.length > 0 ? (
                <Select value={originCity || "all"} onValueChange={(v) => setOriginCity(v === "all" ? "" : v)}>
                  <SelectTrigger className="cursor-pointer">
                    <SelectValue />
                  </SelectTrigger>
                  <SelectContent>
                    <SelectItem value="all">
                      {t("labels.any_city", { ns: "common", defaultValue: "Any city" })}
                    </SelectItem>
                    {cityNames.map((name) => (
                      <SelectItem key={name} value={name}>{name}</SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              ) : (
                <Input
                  placeholder={t("from_city")}
                  value={originCity}
                  onChange={(e) => setOriginCity(e.target.value)}
                />
              )}
            </div>
            <div className="space-y-1">
              <label className="text-xs font-medium text-muted-foreground flex items-center gap-1">
                <MapPinIcon className="w-3 h-3 text-primary" />
                {t("to_city")}
              </label>
              {cityNames.length > 0 ? (
                <Select value={destinationCity || "all"} onValueChange={(v) => setDestinationCity(v === "all" ? "" : v)}>
                  <SelectTrigger className="cursor-pointer">
                    <SelectValue />
                  </SelectTrigger>
                  <SelectContent>
                    <SelectItem value="all">
                      {t("labels.any_city", { ns: "common", defaultValue: "Any city" })}
                    </SelectItem>
                    {cityNames.map((name) => (
                      <SelectItem key={name} value={name}>{name}</SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              ) : (
                <Input
                  placeholder={t("to_city")}
                  value={destinationCity}
                  onChange={(e) => setDestinationCity(e.target.value)}
                />
              )}
            </div>
          </div>

          {/* Date & Price */}
          <div className="grid grid-cols-2 gap-3">
            <div className="space-y-1">
              <label className="text-xs font-medium text-muted-foreground flex items-center gap-1">
                <CalendarIcon className="w-3 h-3" />
                {t("labels.date", { ns: "common", defaultValue: "Date" })}
              </label>
              <Input
                type="date"
                value={departureDate}
                onChange={(e) => setDepartureDate(e.target.value)}
              />
            </div>
            <div className="space-y-1">
              <label className="text-xs font-medium text-muted-foreground flex items-center gap-1">
                <WalletIcon className="w-3 h-3" />
                {t("max_price", { defaultValue: "Max price" })}
              </label>
              <Input
                type="number"
                placeholder="10000"
                value={maxPrice}
                onChange={(e) => setMaxPrice(e.target.value)}
              />
            </div>
          </div>
        </div>
      )}

      {/* Active filter badges (mobile only when filters panel is closed) */}
      {hasActiveFilters && !showFilters && (
        <div className="flex flex-wrap gap-2 md:hidden">
          {countryId !== "all" && countries && (
            <Badge variant="secondary" className="gap-1 cursor-pointer" onClick={() => setCountryId("all")}>
              <GlobeIcon className="w-3 h-3" />
              {countries.find((c) => c._id === countryId)?.name}
              <XIcon className="w-3 h-3" />
            </Badge>
          )}
          {companyId !== "all" && companies && (
            <Badge variant="secondary" className="gap-1 cursor-pointer" onClick={() => setCompanyId("all")}>
              <BuildingIcon className="w-3 h-3" />
              {companies.find((c) => c._id === companyId)?.name}
              <XIcon className="w-3 h-3" />
            </Badge>
          )}
          {originCity && (
            <Badge variant="secondary" className="gap-1 cursor-pointer" onClick={() => setOriginCity("")}>
              <MapPinIcon className="w-3 h-3" />
              {originCity}
              <XIcon className="w-3 h-3" />
            </Badge>
          )}
          {destinationCity && (
            <Badge variant="secondary" className="gap-1 cursor-pointer" onClick={() => setDestinationCity("")}>
              <MapPinIcon className="w-3 h-3" />
              {destinationCity}
              <XIcon className="w-3 h-3" />
            </Badge>
          )}
          {departureDate && (
            <Badge variant="secondary" className="gap-1 cursor-pointer" onClick={() => setDepartureDate("")}>
              <CalendarIcon className="w-3 h-3" />
              {departureDate}
              <XIcon className="w-3 h-3" />
            </Badge>
          )}
          {maxPrice && (
            <Badge variant="secondary" className="gap-1 cursor-pointer" onClick={() => setMaxPrice("")}>
              <WalletIcon className="w-3 h-3" />
              {"≤ " + maxPrice}
              <XIcon className="w-3 h-3" />
            </Badge>
          )}
        </div>
      )}

      {/* Results */}
      <div className="space-y-3">
        <div className="flex items-center justify-between">
          <h2 className="text-sm font-semibold text-muted-foreground uppercase tracking-wider">
            {t("available_trips")}
          </h2>
          {filteredTrips !== undefined && (
            <span className="text-xs text-muted-foreground">
              {filteredTrips.length} {t("labels.results", { ns: "common", defaultValue: "results" })}
            </span>
          )}
        </div>

        {filteredTrips === undefined ? (
          <div className="space-y-3">
            {Array.from({ length: 4 }).map((_, i) => (
              <Skeleton key={i} className="h-32 md:h-24 w-full rounded-xl" />
            ))}
          </div>
        ) : filteredTrips.length === 0 ? (
          <Empty>
            <EmptyHeader>
              <EmptyMedia variant="icon">
                <BusIcon />
              </EmptyMedia>
              <EmptyTitle>{t("no_trips")}</EmptyTitle>
              <EmptyDescription>{t("no_trips_desc")}</EmptyDescription>
            </EmptyHeader>
          </Empty>
        ) : (
          <div className="space-y-3">
            {filteredTrips.map((trip, i) => (
              <motion.div
                key={trip._id}
                initial={{ opacity: 0, y: 12 }}
                animate={{ opacity: 1, y: 0 }}
                transition={{ duration: 0.3, delay: Math.min(i * 0.05, 0.3), ease: "easeOut" }}
              >
                <TripCard trip={trip} lng={lng} t={t} />
              </motion.div>
            ))}
          </div>
        )}
      </div>
    </div>
  );
}

// ─── Enhanced Trip Card ─────────────────────────────────────────────────────

type TripResult = {
  _id: Id<"trips">;
  departureTime: string;
  arrivalTime: string;
  seatsAvailable: number;
  totalSeats: number;
  priceAmount: number;
  currency: string;
  originLoc?: { city: string } | null;
  destLoc?: { city: string } | null;
  origin?: { name: string } | null;
  destination?: { name: string } | null;
  company?: { name: string } | null;
  bus?: { busType: string; name: string; amenities?: string[] } | null;
  route?: { estimatedDurationMinutes: number } | null;
};

function TripCard({ trip, lng, t }: { trip: TripResult; lng?: string; t: (key: string, opts?: Record<string, unknown>) => string }) {
  const percent = getOccupancyPercent(trip.seatsAvailable, trip.totalSeats);
  const color = getOccupancyColor(percent);
  const durationMin = trip.route?.estimatedDurationMinutes;
  const durationStr = durationMin
    ? `${Math.floor(durationMin / 60)}h${durationMin % 60 > 0 ? ` ${durationMin % 60}m` : ""}`
    : null;
  const isSoldOut = trip.seatsAvailable <= 0;

  return (
    <Link to={`/${lng}/trip/${trip._id}`}>
      <Card className={`hover:shadow-lg transition-all cursor-pointer group relative overflow-hidden ${isSoldOut ? "opacity-70" : "hover:border-primary/50"}`}>
        <CardContent className="p-0">
          {/* Sold out overlay */}
          {isSoldOut && (
            <div className="absolute top-3 right-3 z-10">
              <Badge variant="destructive" className="text-[10px] font-bold uppercase tracking-wider">
                {t("sold_out")}
              </Badge>
            </div>
          )}

          {/* Desktop layout: horizontal */}
          <div className="hidden md:flex items-stretch">
            {/* Left: Route timeline */}
            <div className="flex-1 p-5 space-y-3">
              {/* Time + Cities row */}
              <div className="flex items-start gap-4">
                {/* Timeline column */}
                <div className="flex flex-col items-center pt-0.5">
                  <div className="w-3 h-3 rounded-full border-2 border-primary bg-primary/20" />
                  <div className="w-0.5 h-10 bg-gradient-to-b from-primary/60 to-primary/30 my-0.5" />
                  <div className="w-3 h-3 rounded-full border-2 border-primary bg-primary" />
                </div>

                {/* Cities + Times */}
                <div className="flex-1 min-w-0 space-y-3">
                  <div className="flex items-baseline gap-3">
                    <span className="text-sm font-bold text-foreground shrink-0 w-12">
                      {formatTime(trip.departureTime)}
                    </span>
                    <div className="min-w-0">
                      <p className="font-semibold text-sm truncate">{trip.originLoc?.city ?? "?"}</p>
                      <p className="text-[11px] text-muted-foreground truncate">{trip.origin?.name}</p>
                    </div>
                  </div>
                  <div className="flex items-baseline gap-3">
                    <span className="text-sm font-bold text-foreground shrink-0 w-12">
                      {formatTime(trip.arrivalTime)}
                    </span>
                    <div className="min-w-0">
                      <p className="font-semibold text-sm truncate">{trip.destLoc?.city ?? "?"}</p>
                      <p className="text-[11px] text-muted-foreground truncate">{trip.destination?.name}</p>
                    </div>
                  </div>
                </div>
              </div>

              {/* Meta info row */}
              <div className="flex items-center gap-2.5 flex-wrap pl-7">
                <Badge variant="secondary" className="text-[10px] gap-1 font-normal">
                  <CalendarIcon className="w-3 h-3" />
                  {formatDate(trip.departureTime)}
                </Badge>
                {durationStr && (
                  <Badge variant="secondary" className="text-[10px] gap-1 font-normal">
                    <RouteIcon className="w-3 h-3" />
                    {durationStr}
                  </Badge>
                )}
                <Badge variant="secondary" className="text-[10px] gap-1 font-normal capitalize">
                  <BusIcon className="w-3 h-3" />
                  {trip.bus?.busType ?? "Bus"}
                </Badge>
                {trip.bus?.amenities && trip.bus.amenities.length > 0 && (
                  <span className="text-[10px] text-muted-foreground">
                    +{trip.bus.amenities.length} {t("labels.amenities", { ns: "common", defaultValue: "amenities" })}
                  </span>
                )}
              </div>
            </div>

            {/* Middle: Company + Occupancy */}
            <div className="flex flex-col justify-center px-5 py-4 border-l min-w-[170px]">
              <div className="flex items-center gap-2 mb-3">
                <div className="w-7 h-7 rounded-lg bg-primary/10 flex items-center justify-center shrink-0">
                  <BuildingIcon className="w-3.5 h-3.5 text-primary" />
                </div>
                <span className="text-xs font-semibold truncate">{trip.company?.name}</span>
              </div>
              <div className="space-y-2">
                <div className="flex items-center justify-between text-xs">
                  <span className={`font-medium ${color.text}`}>
                    {trip.seatsAvailable} / {trip.totalSeats} {t("labels.seats", { ns: "common", defaultValue: "seats" })}
                  </span>
                </div>
                <div className="h-2 w-full rounded-full bg-muted overflow-hidden">
                  <div
                    className={`h-full rounded-full transition-all duration-500 ${color.bar}`}
                    style={{ width: `${percent}%` }}
                  />
                </div>
                <p className="text-[10px] text-muted-foreground">
                  {isSoldOut
                    ? t("sold_out")
                    : trip.seatsAvailable <= 5
                      ? t("few_seats_left", { defaultValue: "Few seats left!" })
                      : t("seats_available", { defaultValue: "Seats available" })}
                </p>
              </div>
            </div>

            {/* Right: Price + CTA */}
            <div className="flex flex-col items-center justify-center px-6 py-4 border-l min-w-[150px] bg-muted/20">
              <p className="text-2xl font-black text-primary tracking-tight">
                {trip.priceAmount.toLocaleString()}
              </p>
              <p className="text-[11px] text-muted-foreground mb-3">{trip.currency}</p>
              {!isSoldOut && (
                <span className="text-xs text-primary flex items-center gap-1 font-semibold group-hover:gap-2 transition-all">
                  {t("book_now")} <ArrowRightIcon className="w-3.5 h-3.5" />
                </span>
              )}
            </div>
          </div>

          {/* Mobile layout: vertical card */}
          <div className="md:hidden p-4 space-y-3">
            {/* Route */}
            <div className="flex items-start justify-between gap-2">
              <div className="flex-1 min-w-0">
                <div className="flex items-center gap-2">
                  <span className="font-bold text-base">{trip.originLoc?.city ?? "?"}</span>
                  <ArrowRightIcon className="w-3.5 h-3.5 text-muted-foreground shrink-0" />
                  <span className="font-bold text-base">{trip.destLoc?.city ?? "?"}</span>
                </div>
                <p className="text-[11px] text-muted-foreground truncate mt-0.5">
                  {trip.origin?.name} → {trip.destination?.name}
                </p>
              </div>
              <Badge variant="secondary" className="shrink-0 text-[10px]">
                {trip.company?.name}
              </Badge>
            </div>

            {/* Time and date */}
            <div className="flex items-center gap-3 text-xs text-muted-foreground">
              <span className="flex items-center gap-1 font-medium text-foreground">
                <ClockIcon className="w-3.5 h-3.5 text-primary" />
                {formatTime(trip.departureTime)} - {formatTime(trip.arrivalTime)}
              </span>
              <Separator orientation="vertical" className="h-3" />
              <span className="flex items-center gap-1">
                <CalendarIcon className="w-3.5 h-3.5" />
                {formatDate(trip.departureTime)}
              </span>
              {durationStr && (
                <>
                  <Separator orientation="vertical" className="h-3" />
                  <span className="flex items-center gap-1">
                    <RouteIcon className="w-3.5 h-3.5" />
                    {durationStr}
                  </span>
                </>
              )}
            </div>

            {/* Bottom row: seats + price */}
            <div className="flex items-center justify-between pt-1">
              <div className="flex items-center gap-2">
                <div className="flex items-center gap-1.5">
                  <div className="h-1.5 w-12 rounded-full bg-muted overflow-hidden">
                    <div
                      className={`h-full rounded-full ${color.bar}`}
                      style={{ width: `${percent}%` }}
                    />
                  </div>
                  <span className={`text-[11px] font-medium ${color.text}`}>
                    {trip.seatsAvailable}/{trip.totalSeats}
                  </span>
                </div>
                <Badge variant="secondary" className="text-[9px] capitalize">
                  {trip.bus?.busType ?? "Bus"}
                </Badge>
              </div>
              <div className="flex items-center gap-2">
                <span className="font-black text-primary text-base">
                  {trip.priceAmount.toLocaleString()}
                </span>
                <span className="text-[10px] text-muted-foreground">{trip.currency}</span>
              </div>
            </div>
          </div>
        </CardContent>
      </Card>
    </Link>
  );
}
