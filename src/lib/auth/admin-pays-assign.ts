export type CountryAdminPaysHolder = {
  userId: string;
  fullName: string | null;
  email: string | null;
};

const ADMIN_PAYS_TAKEN_PREFIX = "ADMIN_PAYS_COUNTRY_TAKEN";

export function formatAdminPaysTakenMessage(
  holder: CountryAdminPaysHolder,
  countryLabel?: string,
): string {
  const who = holder.fullName?.trim() || holder.email?.trim() || "un autre compte";
  const emailSuffix = holder.email && holder.fullName ? ` (${holder.email})` : "";
  const countrySuffix = countryLabel ? ` pour ${countryLabel}` : "";
  return `Ce pays${countrySuffix} a déjà un admin pays : ${who}${emailSuffix}. Retirez le rôle à ce compte avant d'en attribuer un autre.`;
}

export function parseAdminPaysTakenError(err: unknown): CountryAdminPaysHolder | null {
  const message =
    err instanceof Error
      ? err.message
      : typeof err === "object" && err !== null && "message" in err
        ? String((err as { message: unknown }).message)
        : String(err);

  if (!message.includes(ADMIN_PAYS_TAKEN_PREFIX)) return null;

  const parts = message.split("|");
  if (parts.length < 4) return null;

  return {
    userId: "",
    fullName: parts[1]?.trim() || null,
    email: parts[2]?.trim() || null,
  };
}

export function mapRoleAssignErrorMessage(err: unknown, countryLabel?: string): string {
  const holder = parseAdminPaysTakenError(err);
  if (holder) return formatAdminPaysTakenMessage(holder, countryLabel);

  const message =
    err instanceof Error
      ? err.message
      : typeof err === "object" && err !== null && "message" in err
        ? String((err as { message: unknown }).message)
        : String(err);

  if (/un seul admin pays|admin_pays_country_taken/i.test(message)) {
    return formatAdminPaysTakenMessage({ userId: "", fullName: null, email: null }, countryLabel);
  }

  return message.trim() || "Enregistrement impossible";
}
