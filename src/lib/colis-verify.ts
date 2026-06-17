import { colisPublicReference } from "@/lib/colis-receipt.ts";

const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const COLIS_REF_RE = /^CL-[A-Z0-9]+$/i;

export function normalizeColisReference(raw: string): string {
  const compact = raw.trim().toUpperCase().replace(/\s+/g, "");
  if (!compact) return "";
  if (COLIS_REF_RE.test(compact)) return compact;
  if (compact.startsWith("CL")) return `CL-${compact.replace(/^CL-?/i, "")}`;
  return compact;
}

/** Extrait un code retrait colis (UUID ou CL-…) depuis un scan QR ou une saisie manuelle. */
export function parseColisQrPayload(raw: string): string {
  const trimmed = raw.trim();
  if (!trimmed) return "";

  if (UUID_RE.test(trimmed)) return trimmed;

  const refMatch = trimmed.match(/(CL-[A-Z0-9]+)/i);
  if (refMatch) return normalizeColisReference(refMatch[1]);

  try {
    const url = trimmed.includes("://")
      ? new URL(trimmed)
      : new URL(trimmed, typeof window !== "undefined" ? window.location.origin : "https://tibus.local");
    const parts = url.pathname.split("/").filter(Boolean);
    for (const part of parts) {
      if (UUID_RE.test(part)) return part;
      if (/^CL-/i.test(part)) return normalizeColisReference(part);
    }
    const queryId = url.searchParams.get("colis") ?? url.searchParams.get("id");
    if (queryId && UUID_RE.test(queryId)) return queryId;
  } catch {
    // raw reference
  }

  return normalizeColisReference(trimmed);
}

export function isColisPublicReference(value: string): boolean {
  return COLIS_REF_RE.test(value.trim().toUpperCase());
}

export function colisReferenceFromId(colisId: string): string {
  return colisPublicReference(colisId);
}
