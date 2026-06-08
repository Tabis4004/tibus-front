/** Parse un pourcentage ou montant saisi (accepte virgule FR). Vide => null. */
export function parseOptionalFeeInput(value: string): number | null {
  const trimmed = value.trim();
  if (!trimmed) return null;
  const normalized = trimmed.replace(/\s/g, "").replace(",", ".");
  const parsed = Number(normalized);
  return Number.isFinite(parsed) ? parsed : null;
}

/** Parse obligatoire ; vide => 0 (ex. Y gateway). */
export function parseFeeInputOrZero(value: string): number | null {
  const trimmed = value.trim();
  if (!trimmed) return 0;
  return parseOptionalFeeInput(trimmed);
}

export function formatFeeInput(value: number | null | undefined): string {
  if (value == null || !Number.isFinite(value)) return "";
  return String(value);
}
