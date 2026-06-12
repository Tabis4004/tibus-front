import { useMemo, useState } from "react";
import { Link, useParams } from "react-router-dom";
import { useTranslation } from "react-i18next";
import { useQuery } from "convex/react";
import { format, parseISO } from "date-fns";
import {
  BuildingIcon,
  BusIcon,
  CalendarIcon,
  ClockIcon,
  GlobeIcon,
  MapPinIcon,
  WalletIcon,
  XIcon,
} from "lucide-react";
import { api } from "@/convex/_generated/api.js";
import { Button } from "@/components/ui/button.tsx";
import { Input } from "@/components/ui/input.tsx";
import { Skeleton } from "@/components/ui/skeleton.tsx";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select.tsx";
import { motion } from "motion/react";
import { isSupabaseAuth } from "@/lib/auth/config";
import {
  useSupabaseActiveCompanies,
  useSupabaseCountries,
  useSupabaseSearchTrips,
} from "@/hooks/use-supabase-trip-search.ts";
import { TripCard } from "@/pages/traveler/_components/TripSearchCard.tsx";

const LANDING_TRIP_LIMIT = 12;

function getOccupancyPercent(seatsAvailable: number, totalSeats: number): number {
  if (totalSeats === 0) return 100;
  return Math.round(((totalSeats - seatsAvailable) / totalSeats) * 100);
}

function getOccupancyColor(percent: number) {
  if (percent <= 30) {
    return {
      bar: "bg-emerald-500",
      bg: "bg-emerald-500/15",
      text: "text-emerald-700 dark:text-emerald-400",
      label: "Available",
    };
  }
  if (percent <= 75) {
    return {
      bar: "bg-amber-500",
      bg: "bg-amber-500/15",
      text: "text-amber-700 dark:text-amber-400",
      label: "Filling",
    };
  }
  return {
    bar: "bg-red-500",
    bg: "bg-red-500/15",
    text: "text-red-700 dark:text-red-400",
    label: "Almost full",
  };
}

function SupabaseLandingUpcomingTrips() {
  const { lng } = useParams<{ lng: string }>();
  const { t } = useTranslation("common");
  const { t: tt } = useTranslation("traveler");
  const locale = lng ?? "fr";

  const [countryId, setCountryId] = useState("all");
  const [companyId, setCompanyId] = useState("all");
  const [departureDate, setDepartureDate] = useState("");
  const [maxPrice, setMaxPrice] = useState("");

  const countries = useSupabaseCountries();
  const companies = useSupabaseActiveCompanies();

  const searchArgs = useMemo(() => {
    const args: { departureDate?: string; companyId?: string; countryId?: string } = {};
    if (departureDate) args.departureDate = departureDate;
    if (companyId !== "all") args.companyId = companyId;
    if (countryId !== "all") args.countryId = countryId;
    return args;
  }, [departureDate, companyId, countryId]);

  const trips = useSupabaseSearchTrips(searchArgs);

  const companyOptions = useMemo(() => {
    if (!companies) return [];
    if (countryId === "all") return companies;
    return companies.filter((company) => company.countryId === countryId);
  }, [companies, countryId]);

  const filteredTrips = useMemo(() => {
    if (!trips) return undefined;
    let rows = trips.filter((trip) => trip.seatsAvailable > 0);
    if (maxPrice) {
      const limit = Number(maxPrice);
      if (Number.isFinite(limit)) {
        rows = rows.filter((trip) => trip.priceAmount <= limit);
      }
    }
    return rows.slice(0, LANDING_TRIP_LIMIT);
  }, [trips, maxPrice]);

  const hasActiveFilters =
    countryId !== "all" ||
    companyId !== "all" ||
    departureDate !== "" ||
    maxPrice !== "";

  const clearFilters = () => {
    setCountryId("all");
    setCompanyId("all");
    setDepartureDate("");
    setMaxPrice("");
  };

  return (
    <section className="max-w-6xl mx-auto px-4 sm:px-6 py-16 border-b">
      <div className="text-center mb-8 space-y-2">
        <span className="inline-flex items-center gap-1.5 text-xs font-semibold px-3 py-1.5 rounded-full bg-primary/10 text-primary">
          <BusIcon className="w-3 h-3" />
          {t("landing.upcoming_badge", { defaultValue: "Disponibilité en direct" })}
        </span>
        <h2 className="text-3xl sm:text-4xl font-extrabold tracking-tight">
          {t("landing.upcoming_title", { defaultValue: "Trajets disponibles à venir" })}
        </h2>
        <p className="text-muted-foreground max-w-2xl mx-auto text-sm sm:text-base">
          {t("landing.upcoming_desc", {
            defaultValue:
              "Filtrez par pays, compagnie, date et budget pour trouver votre prochain départ.",
          })}
        </p>
      </div>

      <div className="rounded-2xl border bg-muted/30 p-4 mb-6">
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-3">
          <div className="space-y-1">
            <label className="text-xs font-medium text-muted-foreground flex items-center gap-1">
              <GlobeIcon className="w-3 h-3" />
              {t("labels.country", { defaultValue: "Pays" })}
            </label>
            <Select
              value={countryId}
              onValueChange={(value) => {
                setCountryId(value);
                setCompanyId("all");
              }}
            >
              <SelectTrigger className="h-9 cursor-pointer">
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="all">
                  {t("labels.all_countries", { defaultValue: "Tous les pays" })}
                </SelectItem>
                {countries?.map((country) => (
                  <SelectItem key={country._id} value={country._id}>
                    {country.name}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>

          <div className="space-y-1">
            <label className="text-xs font-medium text-muted-foreground flex items-center gap-1">
              <BuildingIcon className="w-3 h-3" />
              {t("labels.company", { defaultValue: "Compagnie" })}
            </label>
            <Select value={companyId} onValueChange={setCompanyId}>
              <SelectTrigger className="h-9 cursor-pointer">
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="all">
                  {t("labels.all_companies", { defaultValue: "Toutes les compagnies" })}
                </SelectItem>
                {companyOptions.map((company) => (
                  <SelectItem key={company._id} value={company._id}>
                    {company.name}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>

          <div className="space-y-1">
            <label className="text-xs font-medium text-muted-foreground flex items-center gap-1">
              <CalendarIcon className="w-3 h-3" />
              {t("labels.date", { defaultValue: "Date" })}
            </label>
            <Input
              type="date"
              value={departureDate}
              onChange={(event) => setDepartureDate(event.target.value)}
              className="h-9"
            />
          </div>

          <div className="space-y-1">
            <label className="text-xs font-medium text-muted-foreground flex items-center gap-1">
              <WalletIcon className="w-3 h-3" />
              {tt("max_price", { defaultValue: "Coût max" })}
            </label>
            <Input
              type="number"
              min={0}
              placeholder="10000"
              value={maxPrice}
              onChange={(event) => setMaxPrice(event.target.value)}
              className="h-9"
            />
          </div>
        </div>

        {hasActiveFilters && (
          <div className="mt-3 flex justify-end">
            <Button
              variant="ghost"
              size="sm"
              className="h-8 gap-1 text-xs cursor-pointer"
              onClick={clearFilters}
            >
              <XIcon className="w-3 h-3" />
              {t("buttons.clear", { defaultValue: "Effacer" })}
            </Button>
          </div>
        )}
      </div>

      {filteredTrips === undefined ? (
        <div className="space-y-3">
          {Array.from({ length: 3 }).map((_, index) => (
            <Skeleton key={index} className="h-28 w-full rounded-xl" />
          ))}
        </div>
      ) : filteredTrips.length === 0 ? (
        <div className="rounded-xl border border-dashed p-8 text-center">
          <BusIcon className="w-8 h-8 mx-auto text-muted-foreground/50 mb-2" />
          <p className="text-sm text-muted-foreground">
            {t("no_upcoming_trips", { defaultValue: "Aucun trajet à venir pour le moment" })}
          </p>
        </div>
      ) : (
        <div className="space-y-3">
          {filteredTrips.map((trip, index) => (
            <motion.div
              key={trip._id}
              initial={{ opacity: 0, y: 12 }}
              whileInView={{ opacity: 1, y: 0 }}
              viewport={{ once: true }}
              transition={{ duration: 0.3, delay: index * 0.04 }}
            >
              <TripCard trip={trip} lng={locale} t={tt} />
            </motion.div>
          ))}
        </div>
      )}

      <div className="text-center mt-8">
        <Link to={`/${locale}/traveler/search`}>
          <Button variant="outline" className="cursor-pointer gap-2">
            {t("landing.view_all_trips", { defaultValue: "Voir tous les trajets" })}
          </Button>
        </Link>
      </div>
    </section>
  );
}

function ConvexLandingUpcomingTrips() {
  const trips = useQuery(api.trips.listUpcomingTripsPublic, {});
  const { lng } = useParams<{ lng: string }>();
  const { t } = useTranslation("common");
  const locale = lng ?? "fr";

  return (
    <section className="max-w-6xl mx-auto px-4 sm:px-6 py-16 border-b">
      <div className="text-center mb-8 space-y-2">
        <h2 className="text-3xl sm:text-4xl font-extrabold tracking-tight">
          {t("landing.upcoming_title", { defaultValue: "Trajets disponibles à venir" })}
        </h2>
      </div>

      {trips === undefined ? (
        <div className="space-y-3">
          {Array.from({ length: 3 }).map((_, index) => (
            <Skeleton key={index} className="h-28 w-full rounded-xl" />
          ))}
        </div>
      ) : trips.length === 0 ? (
        <div className="rounded-xl border border-dashed p-8 text-center">
          <p className="text-sm text-muted-foreground">
            {t("no_upcoming_trips", { defaultValue: "Aucun trajet à venir pour le moment" })}
          </p>
        </div>
      ) : (
        <div className="space-y-3">
          {trips.slice(0, LANDING_TRIP_LIMIT).map((trip) => {
            const percent = getOccupancyPercent(trip.seatsAvailable, trip.totalSeats);
            const color = getOccupancyColor(percent);
            const departure = parseISO(trip.departureTime);

            return (
              <Link key={trip._id} to={`/${locale}/trip/${trip._id}`} className="block">
                <div className="rounded-xl border bg-card p-4 space-y-3 hover:shadow-md transition-shadow">
                  <div className="flex items-start justify-between gap-2">
                    <div className="flex-1 min-w-0">
                      <div className="flex items-center gap-1.5 text-sm font-semibold truncate">
                        <MapPinIcon className="w-3.5 h-3.5 text-primary shrink-0" />
                        <span className="truncate">{trip.originCity}</span>
                        <span className="text-muted-foreground">→</span>
                        <span className="truncate">{trip.destinationCity}</span>
                      </div>
                      <p className="text-xs text-muted-foreground mt-0.5 truncate">
                        {trip.companyName}
                      </p>
                    </div>
                    <p className="text-sm font-bold text-primary shrink-0">
                      {trip.priceAmount.toLocaleString()} {trip.currency}
                    </p>
                  </div>
                  <div className="flex items-center gap-1.5 text-xs text-muted-foreground">
                    <ClockIcon className="w-3.5 h-3.5" />
                    <span>{format(departure, "EEE dd MMM · HH:mm")}</span>
                  </div>
                  <div className="h-2 w-full rounded-full bg-muted overflow-hidden">
                    <div
                      className={`h-full rounded-full ${color.bar}`}
                      style={{ width: `${percent}%` }}
                    />
                  </div>
                </div>
              </Link>
            );
          })}
        </div>
      )}
    </section>
  );
}

export default function LandingUpcomingTripsSection() {
  if (isSupabaseAuth()) {
    return <SupabaseLandingUpcomingTrips />;
  }
  return <ConvexLandingUpcomingTrips />;
}
