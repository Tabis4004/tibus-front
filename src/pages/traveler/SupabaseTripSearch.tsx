import { useEffect, useMemo, useState } from "react";
import { useParams } from "react-router-dom";
import {
  MapPinIcon,
  CalendarIcon,
  BusIcon,
  BuildingIcon,
  GlobeIcon,
  FilterIcon,
  XIcon,
  WalletIcon,
} from "lucide-react";
import { Input } from "@/components/ui/input.tsx";
import { Button } from "@/components/ui/button.tsx";
import { Badge } from "@/components/ui/badge.tsx";
import { Skeleton } from "@/components/ui/skeleton.tsx";
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
import { useTranslation } from "react-i18next";
import { motion } from "motion/react";
import {
  useSupabaseActiveCompanies,
  useSupabaseCities,
  useSupabaseCountries,
  useSupabaseSearchTrips,
} from "@/hooks/use-supabase-trip-search.ts";
import { TripCard } from "./_components/TripSearchCard.tsx";
import { resolveLandingCountryDefault } from "@/lib/trip-search-defaults.ts";
import {
  Accordion,
  AccordionContent,
  AccordionItem,
  AccordionTrigger,
} from "@/components/ui/accordion.tsx";

export default function SupabaseTripSearch({
  embedded = false,
  hideTitle = false,
  accordionResults = false,
}: {
  embedded?: boolean;
  /** Masque le titre (ex. landing page). */
  hideTitle?: boolean;
  /** Liste des voyages dans un accordéon (landing). */
  accordionResults?: boolean;
}) {
  const { t } = useTranslation("traveler");
  const { t: tc } = useTranslation("common");
  const { lng } = useParams<{ lng: string }>();

  // Filter states
  const [countryId, setCountryId] = useState<string>("all");
  const [companyId, setCompanyId] = useState<string>("all");
  const [originCity, setOriginCity] = useState("");
  const [destinationCity, setDestinationCity] = useState("");
  const [departureDate, setDepartureDate] = useState("");
  const [maxPrice, setMaxPrice] = useState("");
  const [showFilters, setShowFilters] = useState(false);
  const [resultsExpanded, setResultsExpanded] = useState(false);
  const [defaultCountryId, setDefaultCountryId] = useState("all");
  const [defaultCountryApplied, setDefaultCountryApplied] = useState(false);

  const countries = useSupabaseCountries();

  useEffect(() => {
    if (!countries || defaultCountryApplied) return;
    const nextDefault = resolveLandingCountryDefault(countries, embedded);
    setDefaultCountryId(nextDefault);
    if (nextDefault !== "all") setCountryId(nextDefault);
    setDefaultCountryApplied(true);
  }, [countries, defaultCountryApplied, embedded]);
  const companies = useSupabaseActiveCompanies();
  const cities = useSupabaseCities(countryId);

  const searchArgs = useMemo(() => {
    const args: {
      originCity?: string;
      destinationCity?: string;
      departureDate?: string;
      companyId?: string;
      countryId?: string;
    } = {};
    if (originCity.trim()) args.originCity = originCity.trim();
    if (destinationCity.trim()) args.destinationCity = destinationCity.trim();
    if (departureDate) args.departureDate = departureDate;
    if (companyId !== "all") args.companyId = companyId;
    if (countryId !== "all") args.countryId = countryId;
    return args;
  }, [originCity, destinationCity, departureDate, companyId, countryId]);

  const landingLayout = accordionResults;

  const tripsEnabled = !landingLayout || resultsExpanded;
  const trips = useSupabaseSearchTrips(searchArgs, tripsEnabled);

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
    countryId !== defaultCountryId ||
    companyId !== "all" ||
    originCity !== "" ||
    destinationCity !== "" ||
    departureDate !== "" ||
    maxPrice !== "";

  const clearFilters = () => {
    setCountryId(defaultCountryId);
    setCompanyId("all");
    setOriginCity("");
    setDestinationCity("");
    setDepartureDate("");
    setMaxPrice("");
  };

  const resultsBody = (
    <>
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
            <EmptyDescription>
              {embedded && countryId !== "all"
                ? tc("landing.no_trips_country_hint", {
                    defaultValue:
                      "Aucun départ pour ce pays. Essayez « Tous les pays » ou une autre date.",
                  })
                : t("no_trips_desc")}
            </EmptyDescription>
            {embedded && countryId !== "all" && (
              <Button
                variant="outline"
                size="sm"
                className="mt-3"
                onClick={() => setCountryId("all")}
              >
                {tc("labels.all_countries", { defaultValue: "Tous les pays" })}
              </Button>
            )}
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
    </>
  );

  return (
    <div className={embedded ? "space-y-5" : "max-w-6xl mx-auto px-4 py-6 space-y-5"}>
      {landingLayout ? (
        <div className="flex items-start justify-between gap-3">
          <div>
            <h2 className="text-xl md:text-2xl font-extrabold tracking-tight">
              {tc("landing.upcoming_title", { defaultValue: "Trajets disponibles à venir" })}
            </h2>
            <p className="text-muted-foreground text-sm mt-0.5">
              {tc("landing.upcoming_desc", {
                defaultValue:
                  "Filtrez par pays, compagnie, date et budget pour trouver votre prochain départ.",
              })}
            </p>
          </div>
        </div>
      ) : null}

      {/* Header */}
      {embedded && !hideTitle && !accordionResults ? (
        <div className="flex items-center justify-between gap-3">
          <div>
            <h2 className="text-xl md:text-2xl font-extrabold tracking-tight">
              {tc("landing.upcoming_title", { defaultValue: "Trajets disponibles à venir" })}
            </h2>
            <p className="text-muted-foreground text-sm mt-0.5">
              {tc("landing.upcoming_desc", {
                defaultValue:
                  "Filtrez par pays, compagnie, date et budget pour trouver votre prochain départ.",
              })}
            </p>
          </div>
          <Button
            variant="ghost"
            size="sm"
            className="cursor-pointer gap-1.5 relative md:hidden shrink-0"
            onClick={() => setShowFilters(!showFilters)}
          >
            <FilterIcon className="w-4 h-4" />
            {t("labels.filters", { ns: "common", defaultValue: "Filtres" })}
            {hasActiveFilters && (
              <span className="absolute -top-1 -right-1 w-2.5 h-2.5 rounded-full bg-primary" />
            )}
          </Button>
        </div>
      ) : embedded && hideTitle && !accordionResults ? (
        <div className="flex justify-end md:hidden">
          <Button
            variant="ghost"
            size="sm"
            className="cursor-pointer gap-1.5 relative shrink-0"
            onClick={() => setShowFilters(!showFilters)}
          >
            <FilterIcon className="w-4 h-4" />
            {t("labels.filters", { ns: "common", defaultValue: "Filtres" })}
            {hasActiveFilters && (
              <span className="absolute -top-1 -right-1 w-2.5 h-2.5 rounded-full bg-primary" />
            )}
          </Button>
        </div>
      ) : embedded ? null : (
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
      )}

      {/* Filtres — un seul bloc sur la landing ; desktop/mobile séparés ailleurs */}
      <div
        className={
          landingLayout
            ? "rounded-xl border bg-muted/30 p-4"
            : "hidden md:block rounded-xl border bg-muted/30 p-4"
        }
      >
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

      {/* Panneau filtres mobile (page recherche uniquement) */}
      {!landingLayout && showFilters && (
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
      {hasActiveFilters && !showFilters && !landingLayout && (
        <div className="flex flex-wrap gap-2 md:hidden">
          {countryId !== defaultCountryId && countries && (
            <Badge variant="secondary" className="gap-1 cursor-pointer" onClick={() => setCountryId(defaultCountryId)}>
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

      {/* Résultats */}
      {landingLayout ? (
        <Accordion
          type="single"
          collapsible
          defaultValue=""
          className="rounded-xl border bg-background px-4 shadow-sm"
          onValueChange={(value) => setResultsExpanded(value === "results")}
        >
          <AccordionItem value="results" className="border-0">
            <AccordionTrigger className="cursor-pointer py-4 hover:no-underline [&>svg]:size-5">
              <div className="flex w-full items-center justify-between gap-3 pr-2">
                <div className="flex items-center gap-3 text-left">
                  <div className="flex h-9 w-9 shrink-0 items-center justify-center rounded-lg bg-primary/10 text-primary">
                    <BusIcon className="h-4 w-4" />
                  </div>
                  <div>
                    <p className="text-base font-bold tracking-tight">
                      {t("available_trips")}
                    </p>
                    <p className="text-xs font-normal text-muted-foreground">
                      {tc("landing.upcoming_desc", {
                        defaultValue:
                          "Ouvrez pour parcourir les départs et réserver.",
                      })}
                    </p>
                  </div>
                </div>
                {resultsExpanded && filteredTrips !== undefined ? (
                  <span className="text-xs text-muted-foreground shrink-0">
                    {filteredTrips.length}{" "}
                    {t("labels.results", { ns: "common", defaultValue: "résultats" })}
                  </span>
                ) : null}
              </div>
            </AccordionTrigger>
            <AccordionContent className="pb-4">
              {resultsExpanded ? resultsBody : null}
            </AccordionContent>
          </AccordionItem>
        </Accordion>
      ) : (
        <div className="space-y-3">
          <div className="flex items-center justify-between">
            <h2 className="text-sm font-semibold text-muted-foreground uppercase tracking-wider">
              {t("available_trips")}
            </h2>
            {filteredTrips !== undefined && (
              <span className="text-xs text-muted-foreground">
                {filteredTrips.length}{" "}
                {t("labels.results", { ns: "common", defaultValue: "results" })}
              </span>
            )}
          </div>
          {resultsBody}
        </div>
      )}
    </div>
  );
}
