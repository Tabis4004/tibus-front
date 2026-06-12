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

  const qMatch = decoded.match(/[?&](?:q|query)=(-?\d+(?:\.\d+)?),(-?\d+(?:\.\d+)?)/);
  if (qMatch) {
    return { lat: Number(qMatch[1]), lng: Number(qMatch[2]) };
  }

  const dataMatch = decoded.match(/!3d(-?\d+(?:\.\d+)?)!4d(-?\d+(?:\.\d+)?)/);
  if (dataMatch) {
    return { lat: Number(dataMatch[1]), lng: Number(dataMatch[2]) };
  }

  return null;
}
