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
