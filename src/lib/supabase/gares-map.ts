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
  googleMapsLink: string;
  lat: number | null;
  lng: number | null;
};

function companyNameFromJoin(
  value: { name: string } | { name: string }[] | null | undefined,
): string {
  if (!value) return "";
  if (Array.isArray(value)) return value[0]?.name ?? "";
  return value.name ?? "";
}

export async function listGaresMapPointsSupabase(
  options?: { googleMapsApiKey?: string },
): Promise<GareMapPoint[]> {
  const { data, error } = await supabase
    .from("Gares")
    .select("id, name, googleMapsLink, latitude, longitude, Companies(name)")
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

      return {
        id: String(row.id),
        name: String(row.name),
        companyName: companyNameFromJoin(
          row.Companies as { name: string } | { name: string }[] | null,
        ),
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
