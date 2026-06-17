/** Normalise un numéro saisi vers le format E.164 attendu par Supabase Auth. */
export function normalizePhoneE164(input: string): string {
  const trimmed = input.trim();
  const cleaned = trimmed.replace(/[^\d+]/g, "");

  if (cleaned.startsWith("+")) {
    const digits = cleaned.slice(1).replace(/\D/g, "");
    if (digits.length < 9 || digits.length > 15) {
      throw new Error("Numéro de téléphone invalide.");
    }
    return `+${digits}`;
  }

  const digits = cleaned.replace(/\D/g, "");
  if (digits.length >= 10 && digits.length <= 15) {
    return `+${digits}`;
  }

  throw new Error("Indiquez le code pays, par ex. +225 07 00 00 00 00.");
}
