import { Link } from "react-router-dom";
import {
  CalendarIcon,
  ClockIcon,
  BusIcon,
  ArrowRightIcon,
  BuildingIcon,
  RouteIcon,
} from "lucide-react";
import { Card, CardContent } from "@/components/ui/card.tsx";
import { Badge } from "@/components/ui/badge.tsx";
import { Separator } from "@/components/ui/separator.tsx";
import { format, parseISO } from "date-fns";
import type { TripSearchResult } from "@/lib/supabase/trip-search";

export type TripResult = TripSearchResult;

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
  if (percent <= 30) {
    return {
      bar: "bg-emerald-500",
      text: "text-emerald-600 dark:text-emerald-400",
      label: "low",
    };
  }
  if (percent <= 75) {
    return {
      bar: "bg-amber-500",
      text: "text-amber-600 dark:text-amber-400",
      label: "medium",
    };
  }
  return {
    bar: "bg-red-500",
    text: "text-red-600 dark:text-red-400",
    label: "high",
  };
}

export function TripCard({
  trip,
  lng,
  t,
}: {
  trip: TripResult;
  lng?: string;
  t: (key: string, opts?: Record<string, unknown>) => string;
}) {
  const percent = getOccupancyPercent(trip.seatsAvailable, trip.totalSeats);
  const color = getOccupancyColor(percent);
  const durationMin = trip.route?.estimatedDurationMinutes;
  const durationStr = durationMin
    ? `${Math.floor(durationMin / 60)}h${durationMin % 60 > 0 ? ` ${durationMin % 60}m` : ""}`
    : null;
  const isSoldOut = trip.seatsAvailable <= 0;

  return (
    <Link to={`/${lng}/trip/${trip._id}`}>
      <Card
        className={`hover:shadow-lg transition-all cursor-pointer group relative overflow-hidden ${isSoldOut ? "opacity-70" : "hover:border-primary/50"}`}
      >
        <CardContent className="p-0">
          {isSoldOut && (
            <div className="absolute top-3 right-3 z-10">
              <Badge
                variant="destructive"
                className="text-[10px] font-bold uppercase tracking-wider"
              >
                {t("sold_out")}
              </Badge>
            </div>
          )}

          <div className="hidden md:flex items-stretch">
            <div className="flex-1 p-5 space-y-3">
              <div className="flex items-start gap-4">
                <div className="flex flex-col items-center pt-0.5">
                  <div className="w-3 h-3 rounded-full border-2 border-primary bg-primary/20" />
                  <div className="w-0.5 h-10 bg-gradient-to-b from-primary/60 to-primary/30 my-0.5" />
                  <div className="w-3 h-3 rounded-full border-2 border-primary bg-primary" />
                </div>
                <div className="flex-1 min-w-0 space-y-3">
                  <div className="flex items-baseline gap-3">
                    <span className="text-sm font-bold text-foreground shrink-0 w-12">
                      {formatTime(trip.departureTime)}
                    </span>
                    <div className="min-w-0">
                      <p className="font-semibold text-sm truncate">
                        {trip.originLoc?.city ?? "?"}
                      </p>
                      <p className="text-[11px] text-muted-foreground truncate">
                        {trip.origin?.name}
                      </p>
                    </div>
                  </div>
                  <div className="flex items-baseline gap-3">
                    <span className="text-sm font-bold text-foreground shrink-0 w-12">
                      {formatTime(trip.arrivalTime)}
                    </span>
                    <div className="min-w-0">
                      <p className="font-semibold text-sm truncate">
                        {trip.destLoc?.city ?? "?"}
                      </p>
                      <p className="text-[11px] text-muted-foreground truncate">
                        {trip.destination?.name}
                      </p>
                    </div>
                  </div>
                </div>
              </div>
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
              </div>
            </div>
            <div className="flex flex-col justify-center px-5 py-4 border-l min-w-[170px]">
              <div className="flex items-center gap-2 mb-3">
                <div className="w-7 h-7 rounded-lg bg-primary/10 flex items-center justify-center shrink-0">
                  <BuildingIcon className="w-3.5 h-3.5 text-primary" />
                </div>
                <span className="text-xs font-semibold truncate">
                  {trip.company?.name}
                </span>
              </div>
              <div className="space-y-2">
                <div className="flex items-center justify-between text-xs">
                  <span className={`font-medium ${color.text}`}>
                    {trip.seatsAvailable} / {trip.totalSeats}{" "}
                    {t("labels.seats", { ns: "common", defaultValue: "seats" })}
                  </span>
                </div>
                <div className="h-2 w-full rounded-full bg-muted overflow-hidden">
                  <div
                    className={`h-full rounded-full transition-all duration-500 ${color.bar}`}
                    style={{ width: `${percent}%` }}
                  />
                </div>
              </div>
            </div>
            <div className="flex flex-col items-center justify-center px-6 py-4 border-l min-w-[150px] bg-muted/20">
              <p className="text-2xl font-black text-primary tracking-tight">
                {trip.priceAmount.toLocaleString()}
              </p>
              <p className="text-[11px] text-muted-foreground mb-3">
                {trip.currency}
              </p>
              {!isSoldOut && (
                <span className="text-xs text-primary flex items-center gap-1 font-semibold group-hover:gap-2 transition-all">
                  {t("book_now")} <ArrowRightIcon className="w-3.5 h-3.5" />
                </span>
              )}
            </div>
          </div>

          <div className="md:hidden p-4 space-y-3">
            <div className="flex items-start justify-between gap-2">
              <div className="flex-1 min-w-0">
                <div className="flex items-center gap-2">
                  <span className="font-bold text-base">
                    {trip.originLoc?.city ?? "?"}
                  </span>
                  <ArrowRightIcon className="w-3.5 h-3.5 text-muted-foreground shrink-0" />
                  <span className="font-bold text-base">
                    {trip.destLoc?.city ?? "?"}
                  </span>
                </div>
                <p className="text-[11px] text-muted-foreground truncate mt-0.5">
                  {trip.origin?.name} → {trip.destination?.name}
                </p>
              </div>
              <Badge variant="secondary" className="shrink-0 text-[10px]">
                {trip.company?.name}
              </Badge>
            </div>
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
            </div>
            <div className="flex items-center justify-between pt-1">
              <span className={`text-[11px] font-medium ${color.text}`}>
                {trip.seatsAvailable}/{trip.totalSeats}
              </span>
              <div className="flex items-center gap-2">
                <span className="font-black text-primary text-base">
                  {trip.priceAmount.toLocaleString()}
                </span>
                <span className="text-[10px] text-muted-foreground">
                  {trip.currency}
                </span>
              </div>
            </div>
          </div>
        </CardContent>
      </Card>
    </Link>
  );
}
