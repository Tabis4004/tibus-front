const GOOGLE_MAP_HOST_PATTERN =
  /maps\.google|google\.com\/maps|goo\.gl\/maps|maps\.app\.goo\.gl/i;

export function isGoogleMapsLink(value: string | null | undefined): boolean {
  const normalized = String(value ?? "").trim();
  if (!normalized.startsWith("https://")) return false;
  return GOOGLE_MAP_HOST_PATTERN.test(normalized);
}

export function parseGoogleMapsCoordinates(
  url: string,
): { lat: number; lng: number } | null {
  const decoded = decodeURIComponent(url.trim());

  const atMatch = decoded.match(/@(-?\d+(?:\.\d+)?),(-?\d+(?:\.\d+)?)/);
  if (atMatch) {
    return { lat: Number(atMatch[1]), lng: Number(atMatch[2]) };
  }

  const qMatch = decoded.match(/[?&](?:q|query|ll)=(-?\d+(?:\.\d+)?),(-?\d+(?:\.\d+)?)/);
  if (qMatch) {
    return { lat: Number(qMatch[1]), lng: Number(qMatch[2]) };
  }

  const dataMatch = decoded.match(/!3d(-?\d+(?:\.\d+)?)!4d(-?\d+(?:\.\d+)?)/);
  if (dataMatch) {
    return { lat: Number(dataMatch[1]), lng: Number(dataMatch[2]) };
  }

  const centerMatch = decoded.match(/[?&]center=(-?\d+(?:\.\d+)?),(-?\d+(?:\.\d+)?)/);
  if (centerMatch) {
    return { lat: Number(centerMatch[1]), lng: Number(centerMatch[2]) };
  }

  return null;
}

export function resolveGareCoordinates(input: {
  googleMapsLink?: string | null;
  latitude?: number | null;
  longitude?: number | null;
}): { lat: number; lng: number } | null {
  if (
    input.latitude != null &&
    input.longitude != null &&
    Number.isFinite(input.latitude) &&
    Number.isFinite(input.longitude)
  ) {
    return { lat: input.latitude, lng: input.longitude };
  }

  const link = String(input.googleMapsLink ?? "").trim();
  if (!link || !isGoogleMapsLink(link)) return null;
  return parseGoogleMapsCoordinates(link);
}

export async function geocodeGareName(
  name: string,
  apiKey: string,
): Promise<{ lat: number; lng: number } | null> {
  const query = name.trim();
  if (!query || !apiKey) return null;

  const url = new URL("https://maps.googleapis.com/maps/api/geocode/json");
  url.searchParams.set("address", query);
  url.searchParams.set("key", apiKey);

  const response = await fetch(url);
  if (!response.ok) return null;

  const payload = (await response.json()) as {
    status?: string;
    results?: Array<{ geometry?: { location?: { lat?: number; lng?: number } } }>;
  };

  if (payload.status !== "OK" || !payload.results?.length) return null;

  const location = payload.results[0]?.geometry?.location;
  if (location?.lat == null || location?.lng == null) return null;

  return { lat: location.lat, lng: location.lng };
}
