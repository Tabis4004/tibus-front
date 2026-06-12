import type { GareMapPoint } from "@/lib/supabase/gares-map.ts";

const EARTH_RADIUS_KM = 6371;

function toRadians(value: number) {
  return (value * Math.PI) / 180;
}

export function distanceKm(
  a: { lat: number; lng: number },
  b: { lat: number; lng: number },
): number {
  const dLat = toRadians(b.lat - a.lat);
  const dLng = toRadians(b.lng - a.lng);
  const lat1 = toRadians(a.lat);
  const lat2 = toRadians(b.lat);

  const h =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(lat1) * Math.cos(lat2) * Math.sin(dLng / 2) ** 2;

  return 2 * EARTH_RADIUS_KM * Math.asin(Math.min(1, Math.sqrt(h)));
}

export function garesSpreadKm(gares: GareMapPoint[]): number {
  const points = gares.filter((gare) => gare.lat != null && gare.lng != null);
  if (points.length < 2) return 0;

  let maxDistance = 0;
  for (let i = 0; i < points.length; i += 1) {
    for (let j = i + 1; j < points.length; j += 1) {
      const d = distanceKm(
        { lat: points[i].lat as number, lng: points[i].lng as number },
        { lat: points[j].lat as number, lng: points[j].lng as number },
      );
      if (d > maxDistance) maxDistance = d;
    }
  }

  return maxDistance;
}

export function cityOptionsFromGares(gares: GareMapPoint[]): string[] {
  return [...new Set(gares.map((gare) => gare.cityName.trim()).filter(Boolean))].sort((a, b) =>
    a.localeCompare(b, "fr"),
  );
}

/** Au-delà de 40 km entre gares, une carte pays masque le pin sous le nom de la ville. */
export const CITY_MAP_ZOOM_THRESHOLD_KM = 40;
