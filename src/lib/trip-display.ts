import { format, parseISO } from "date-fns";

export type TripItineraryLabelInput = {
  originCity: string;
  originGare: string;
  destinationCity: string;
  destinationGare: string;
  departureTime: string;
  arrivalTime?: string | null;
  priceAmount?: number | null;
  currency?: string | null;
};

export function formatTripItineraryLabel(input: TripItineraryLabelInput): string {
  const departure = parseISO(input.departureTime);
  const depDate = format(departure, "dd/MM/yyyy");
  const depTime = format(departure, "HH:mm");
  const pricePart =
    input.priceAmount != null && input.currency
      ? ` ${input.priceAmount.toLocaleString()} ${input.currency}`
      : "";
  const arrivalPart = input.arrivalTime
    ? `, ${format(parseISO(input.arrivalTime), "HH:mm")}`
    : "";

  return `${input.originCity}, ${input.originGare} ${depDate} ${depTime}${pricePart} vers ${input.destinationCity}, ${input.destinationGare}${arrivalPart}`;
}

export function formatRouteOptionLabel(input: {
  originCity: string;
  originGare: string;
  destCity: string;
  destGare: string;
  price: number;
  currency: string;
}): string {
  return `${input.originCity}, ${input.originGare} vers ${input.destCity}, ${input.destGare} — ${input.price.toLocaleString()} ${input.currency}`;
}

export function cityNameFromGareRow(
  gareName: string,
  linkedCityName?: string | null,
  cityNames: string[] = [],
): string {
  if (linkedCityName?.trim()) return linkedCityName.trim();

  const parts = gareName.split("—");
  if (parts.length > 1) return parts[parts.length - 1].trim();

  const normalized = gareName.replace(/^Gare\s+/i, "").trim();
  const match = cityNames.find((city) =>
    normalized.toLowerCase().includes(city.toLowerCase()),
  );
  return match ?? normalized;
}
