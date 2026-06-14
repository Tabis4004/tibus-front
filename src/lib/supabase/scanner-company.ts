import { supabase } from "@/lib/supabase";

const OWNER_COMPANY_STORAGE_PREFIX = "tibus:owner-company:";
const SCANNER_ROLE_NAMES = ["owner", "controleur", "vendeur", "chauffeur"] as const;

function roleNameFromJoin(
  role: { name: string } | { name: string }[] | null | undefined,
): string | null {
  if (!role) return null;
  if (Array.isArray(role)) return role[0]?.name ?? null;
  return role.name ?? null;
}

export async function resolveScannerCompanyId(
  appUserId: string,
  roles: readonly string[],
): Promise<string | null> {
  if (!appUserId) return null;

  if (roles.includes("owner")) {
    const stored = localStorage.getItem(`${OWNER_COMPANY_STORAGE_PREFIX}${appUserId}`);
    if (stored) return stored;
  }

  const { data, error } = await supabase
    .from("UserRoles")
    .select("companyId, Role(name)")
    .eq("userId", appUserId);

  if (error) throw error;

  for (const roleName of SCANNER_ROLE_NAMES) {
    const match = (data ?? []).find((row) => {
      const name = roleNameFromJoin(row.Role as { name: string } | { name: string }[] | null);
      return name === roleName && Boolean(row.companyId);
    });
    if (match?.companyId) return String(match.companyId);
  }

  return null;
}
