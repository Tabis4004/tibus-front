export function normalizeTicketReference(raw: string): string {
  const compact = raw.trim().toUpperCase().replace(/\s+/g, "");
  if (!compact) return "";
  if (compact.startsWith("TB-")) return compact;
  return `TB-${compact.replace(/^TB-?/i, "")}`;
}

export function buildTicketVerifyUrl(input: {
  reference: string;
  verifyToken?: string | null;
  lng?: string;
  origin?: string;
}): string {
  const origin = input.origin ?? (typeof window !== "undefined" ? window.location.origin : "");
  const lng = input.lng ?? "fr";
  const base = `${origin}/${lng}/verify/${encodeURIComponent(input.reference)}`;
  if (input.verifyToken) {
    return `${base}?t=${encodeURIComponent(input.verifyToken)}`;
  }
  return base;
}

export function parseTicketQrPayload(raw: string): {
  reference: string;
  token: string | null;
} {
  const trimmed = raw.trim();
  if (!trimmed) return { reference: "", token: null };

  try {
    const url = trimmed.includes("://")
      ? new URL(trimmed)
      : new URL(trimmed, typeof window !== "undefined" ? window.location.origin : "https://tibus.local");
    const token = url.searchParams.get("t");
    const parts = url.pathname.split("/").filter(Boolean);
    const verifyIdx = parts.findIndex((part) => part.toLowerCase() === "verify");
    const reference = verifyIdx >= 0 ? parts[verifyIdx + 1] : parts[parts.length - 1];
    if (reference) {
      return {
        reference: normalizeTicketReference(decodeURIComponent(reference)),
        token,
      };
    }
  } catch {
    // fall through to raw reference parsing
  }

  const tokenMatch = trimmed.match(/[?&]t=([^&\s]+)/i);
  const token = tokenMatch ? decodeURIComponent(tokenMatch[1]) : null;
  const refMatch = trimmed.match(/(TB-[A-Z0-9]+)/i);
  if (refMatch) {
    return { reference: normalizeTicketReference(refMatch[1]), token };
  }

  return { reference: normalizeTicketReference(trimmed), token };
}
