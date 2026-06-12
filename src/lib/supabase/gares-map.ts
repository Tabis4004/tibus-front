import { supabase } from "@/lib/supabase";
import {
  geocodeGareName,
  isGoogleMapsLink,
  resolveGareCoordinates,
} from "@/lib/google-maps-link.ts";

export type GareMapPoint = {
  id: string;
  name: string;
  companyName: string;
  countryName: string;
  cityName: string;
  googleMapsLink: string;
  lat: number | null;
  lng: number | null;
};

export type GaresByCountry = {
  countryName: string;
  cities: {
    cityName: string;
    gares: GareMapPoint[];
  }[];
}[];

function companyNameFromJoin(
  value: { name: string; Countries?: { name: string } | { name: string }[] | null } | { name: string; Countries?: { name: string } | { name: string }[] | null }[] | null | undefined,
): { companyName: string; countryName: string } {
  const company = Array.isArray(value) ? value[0] : value;
  if (!company) return { companyName: "", countryName: "" };

  const countries = company.Countries;
  const country = Array.isArray(countries) ? countries[0] : countries;

  return {
    companyName: company.name ?? "",
    countryName: country?.name ?? "",
  };
}

export function cityFromGareName(gareName: string): string {
  const parts = gareName.split("—");
  if (parts.length > 1) return parts[parts.length - 1].trim();
  return gareName.replace(/^Gare\s+/i, "").trim();
}

export function groupGaresByCountryAndCity(gares: GareMapPoint[]): GaresByCountry {
  const byCountry = new Map<string, Map<string, GareMapPoint[]>>();

  for (const gare of gares) {
    const country = gare.countryName.trim() || "Autre";
    const city = gare.cityName.trim() || "Autre";
    if (!byCountry.has(country)) byCountry.set(country, new Map());
    const cities = byCountry.get(country)!;
    if (!cities.has(city)) cities.set(city, []);
    cities.get(city)!.push(gare);
  }

  return [...byCountry.entries()]
    .sort(([a], [b]) => a.localeCompare(b, "fr"))
    .map(([countryName, cities]) => ({
      countryName,
      cities: [...cities.entries()]
        .sort(([a], [b]) => a.localeCompare(b, "fr"))
        .map(([cityName, cityGares]) => ({
          cityName,
          gares: cityGares.sort((a, b) => a.name.localeCompare(b.name, "fr")),
        })),
    }));
}

export async function listGaresMapPointsSupabase(
  options?: { googleMapsApiKey?: string },
): Promise<GareMapPoint[]> {
  const { data, error } = await supabase
    .from("Gares")
    .select("id, name, googleMapsLink, latitude, longitude, Companies(name, Countries(name))")
    .not("googleMapsLink", "is", null)
    .order("name");

  if (error) throw error;

  const baseRows = (data ?? [])
    .map((row) => {
      const link = String(row.googleMapsLink ?? "").trim();
      if (!isGoogleMapsLink(link)) return null;

      const coords = resolveGareCoordinates({
        googleMapsLink: link,
        latitude: row.latitude as number | null,
        longitude: row.longitude as number | null,
      });

      const { companyName, countryName } = companyNameFromJoin(
        row.Companies as
          | { name: string; Countries?: { name: string } | { name: string }[] | null }
          | { name: string; Countries?: { name: string } | { name: string }[] | null }[]
          | null,
      );

      return {
        id: String(row.id),
        name: String(row.name),
        companyName,
        countryName,
        cityName: cityFromGareName(String(row.name)),
        googleMapsLink: link,
        lat: coords?.lat ?? null,
        lng: coords?.lng ?? null,
      };
    })
    .filter((row): row is GareMapPoint => Boolean(row));

  const apiKey = options?.googleMapsApiKey?.trim();
  if (!apiKey) return baseRows;

  const enriched: GareMapPoint[] = [];
  for (const gare of baseRows) {
    if (gare.lat != null && gare.lng != null) {
      enriched.push(gare);
      continue;
    }

    const geocoded = await geocodeGareName(gare.name, apiKey);
    enriched.push(
      geocoded
        ? { ...gare, lat: geocoded.lat, lng: geocoded.lng }
        : gare,
    );
  }

  return enriched;
}

export function coordinatesFromGoogleMapsLink(
  googleMapsLink?: string | null,
): { latitude: number | null; longitude: number | null } {
  const coords = resolveGareCoordinates({ googleMapsLink });
  return {
    latitude: coords?.lat ?? null,
    longitude: coords?.lng ?? null,
  };
}
