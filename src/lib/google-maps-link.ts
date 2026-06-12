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

/** Préfère !3d/!4d (pin exact) avant @ (centre de la vue carte). */
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

type ResolvedLinkRow = {
  link: string;
  lat: number | null;
  lng: number | null;
  expandedUrl?: string | null;
};

export async function resolveGoogleMapsLinksBatch(
  links: string[],
): Promise<Map<string, { lat: number; lng: number }>> {
  const uniqueLinks = [...new Set(links.map((link) => link.trim()).filter(Boolean))];
  if (!uniqueLinks.length) return new Map();

  const { supabase } = await import("@/lib/supabase");
  const { data, error } = await supabase.functions.invoke("resolve-google-maps-link", {
    body: { links: uniqueLinks },
  });

  if (error) throw error;

  const rows = (data as { results?: ResolvedLinkRow[] } | null)?.results ?? [];
  const byLink = new Map<string, { lat: number; lng: number }>();

  for (const row of rows) {
    if (row.lat == null || row.lng == null) continue;
    byLink.set(row.link, { lat: row.lat, lng: row.lng });
  }

  return byLink;
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
