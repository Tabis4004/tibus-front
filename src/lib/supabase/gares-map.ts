import { supabase } from "@/lib/supabase";
import {
  geocodeGareName,
  isGoogleMapsLink,
  parseGoogleMapsCoordinates,
  resolveGareCoordinates,
  resolveGareStationsBatch,
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
  options?: { googleMapsApiKey?: string; companyId?: string },
): Promise<GareMapPoint[]> {
  let query = supabase
    .from("Gares")
    .select(
      "id, name, googleMapsLink, latitude, longitude, Companies!inner(name, isActive, Countries(name))",
    )
    .eq("Companies.isActive", true)
    .not("googleMapsLink", "is", null)
    .order("name");

  if (options?.companyId) {
    query = query.eq("companyId", options.companyId);
  }

  const { data, error } = await query;

  if (error) throw error;

  type RawGareRow = {
    id: string;
    name: string;
    googleMapsLink: string;
    dbLat: number | null;
    dbLng: number | null;
    companyName: string;
    countryName: string;
    cityName: string;
  };

  const rawRows: RawGareRow[] = (data ?? [])
    .map((row) => {
      const link = String(row.googleMapsLink ?? "").trim();
      if (!isGoogleMapsLink(link)) return null;

      const { companyName, countryName } = companyNameFromJoin(
        row.Companies as
          | { name: string; Countries?: { name: string } | { name: string }[] | null }
          | { name: string; Countries?: { name: string } | { name: string }[] | null }[]
          | null,
      );

      return {
        id: String(row.id),
        name: String(row.name),
        googleMapsLink: link,
        dbLat: row.latitude as number | null,
        dbLng: row.longitude as number | null,
        companyName,
        countryName,
        cityName: cityFromGareName(String(row.name)),
      };
    })
    .filter((row): row is RawGareRow => Boolean(row));

  let resolvedByLink = new Map<string, { lat: number; lng: number }>();
  try {
    resolvedByLink = await resolveGareStationsBatch(
      rawRows.map((row) => ({
        link: row.googleMapsLink,
        name: row.name,
        city: row.cityName,
        country: row.countryName,
      })),
    );
  } catch {
    resolvedByLink = new Map();
  }

  const withCoords: GareMapPoint[] = rawRows.map((row) => {
    const fromLink =
      resolvedByLink.get(row.googleMapsLink) ??
      parseGoogleMapsCoordinates(row.googleMapsLink) ??
      (row.dbLat != null && row.dbLng != null
        ? { lat: row.dbLat, lng: row.dbLng }
        : null);

    return {
      id: row.id,
      name: row.name,
      companyName: row.companyName,
      countryName: row.countryName,
      cityName: row.cityName,
      googleMapsLink: row.googleMapsLink,
      lat: fromLink?.lat ?? null,
      lng: fromLink?.lng ?? null,
    };
  });

  const apiKey = options?.googleMapsApiKey?.trim();
  if (!apiKey) return withCoords;

  const enriched: GareMapPoint[] = [];
  for (const gare of withCoords) {
    if (gare.lat != null && gare.lng != null) {
      enriched.push(gare);
      continue;
    }

    const geocoded = await geocodeGareName(`${gare.name}, ${gare.cityName}, ${gare.countryName}`, apiKey);
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
  const link = String(googleMapsLink ?? "").trim();
  const fromLink = link ? parseGoogleMapsCoordinates(link) : null;
  if (fromLink) {
    return { latitude: fromLink.lat, longitude: fromLink.lng };
  }

  const coords = resolveGareCoordinates({ googleMapsLink });
  return {
    latitude: coords?.lat ?? null,
    longitude: coords?.lng ?? null,
  };
}

export async function coordinatesFromGoogleMapsLinkAsync(
  googleMapsLink?: string | null,
  context?: { name?: string; city?: string; country?: string },
): Promise<{ latitude: number | null; longitude: number | null }> {
  const link = String(googleMapsLink ?? "").trim();
  if (!link) {
    return { latitude: null, longitude: null };
  }

  const direct = parseGoogleMapsCoordinates(link);
  if (direct) {
    return { latitude: direct.lat, longitude: direct.lng };
  }

  try {
    const resolved = await resolveGareStationsBatch([
      {
        link,
        name: context?.name,
        city: context?.city,
        country: context?.country,
      },
    ]);
    const coords = resolved.get(link);
    if (coords) return { latitude: coords.lat, longitude: coords.lng };
  } catch {
    // ignore
  }

  return { latitude: null, longitude: null };
}
