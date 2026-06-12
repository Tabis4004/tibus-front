const GOOGLE_MAP_HOST_PATTERN =
  /maps\.google|google\.com\/maps|goo\.gl\/maps|maps\.app\.goo\.gl/i;

export function isGoogleMapsLink(value: string | null | undefined): boolean {
  const normalized = String(value ?? "").trim();
  if (!normalized.startsWith("https://")) return false;
  return GOOGLE_MAP_HOST_PATTERN.test(normalized);
}

export function isShortGoogleMapsLink(url: string): boolean {
  return /maps\.app\.goo\.gl|goo\.gl\/maps/i.test(url.trim());
}

export function parseGoogleMapsCoordinates(
  url: string,
): { lat: number; lng: number } | null {
  const decoded = decodeURIComponent(url.trim());

  const placeMatch = decoded.match(/!3d(-?\d+(?:\.\d+)?)!4d(-?\d+(?:\.\d+)?)/);
  if (placeMatch) {
    return { lat: Number(placeMatch[1]), lng: Number(placeMatch[2]) };
  }

  const searchMatch = decoded.match(
    /\/maps\/search\/(-?\d+(?:\.\d+)?),\s*\+?(-?\d+(?:\.\d+)?)/i,
  );
  if (searchMatch) {
    return { lat: Number(searchMatch[1]), lng: Number(searchMatch[2]) };
  }

  const qMatch = decoded.match(/[?&](?:q|query|ll)=(-?\d+(?:\.\d+)?),(-?\d+(?:\.\d+)?)/);
  if (qMatch) {
    return { lat: Number(qMatch[1]), lng: Number(qMatch[2]) };
  }

  const placeQueryMatch = decoded.match(/\/maps\/place\/[^/]+\/(-?\d+(?:\.\d+)?),(-?\d+(?:\.\d+)?)/);
  if (placeQueryMatch) {
    return { lat: Number(placeQueryMatch[1]), lng: Number(placeQueryMatch[2]) };
  }

  const centerMatch = decoded.match(/[?&]center=(-?\d+(?:\.\d+)?),(-?\d+(?:\.\d+)?)/);
  if (centerMatch) {
    return { lat: Number(centerMatch[1]), lng: Number(centerMatch[2]) };
  }

  const atMatch = decoded.match(/@(-?\d+(?:\.\d+)?),(-?\d+(?:\.\d+)?)/);
  if (atMatch) {
    return { lat: Number(atMatch[1]), lng: Number(atMatch[2]) };
  }

  return null;
}

export async function expandGoogleMapsLink(link: string): Promise<string | null> {
  const normalized = link.trim();
  if (!normalized || !isGoogleMapsLink(normalized)) return null;
  if (!isShortGoogleMapsLink(normalized)) return normalized;

  try {
    const response = await fetch(normalized, { redirect: "follow" });
    const finalUrl = response.url?.trim();
    return finalUrl && isGoogleMapsLink(finalUrl) ? finalUrl : null;
  } catch {
    return null;
  }
}

export async function geocodeStationNominatim(input: {
  name: string;
  city?: string;
  country?: string;
}): Promise<{ lat: number; lng: number } | null> {
  const parts = [input.name.trim(), input.city?.trim(), input.country?.trim()].filter(Boolean);
  if (!parts.length) return null;

  const url = new URL("https://nominatim.openstreetmap.org/search");
  url.searchParams.set("q", parts.join(", "));
  url.searchParams.set("format", "json");
  url.searchParams.set("limit", "8");

  const response = await fetch(url.toString(), {
    headers: { "User-Agent": "tibus-app/1.0 (gare-map-resolve)" },
  });
  if (!response.ok) return null;

  const rows = (await response.json()) as Array<{
    lat?: string;
    lon?: string;
    class?: string;
    type?: string;
  }>;

  const preferred =
    rows.find((row) => row.class === "amenity" && row.type === "bus_station") ??
    rows.find((row) => row.type === "bus_stop") ??
    rows.find((row) => row.class === "amenity" && row.type === "station") ??
    rows[0];

  if (!preferred?.lat || !preferred?.lon) return null;

  const lat = Number(preferred.lat);
  const lng = Number(preferred.lon);
  if (!Number.isFinite(lat) || !Number.isFinite(lng)) return null;

  return { lat, lng };
}

export async function resolveGoogleMapsLinkCoordinates(
  link: string,
): Promise<{ lat: number; lng: number; expandedUrl?: string } | null> {
  const normalized = link.trim();
  if (!normalized || !isGoogleMapsLink(normalized)) return null;

  const direct = parseGoogleMapsCoordinates(normalized);
  if (direct) return direct;

  const expandedUrl = await expandGoogleMapsLink(normalized);
  if (!expandedUrl) return null;

  const coords = parseGoogleMapsCoordinates(expandedUrl);
  if (!coords) return null;

  return { ...coords, expandedUrl };
}
