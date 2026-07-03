import {
  hasSellerManualAccess,
  isSellerOnlyManualProfile,
} from "@/lib/seller-manual-access.ts";

export type ManualNavItem = {
  toSuffix: string;
  labelKey: string;
  labelDefault: string;
  descKey: string;
  descDefault: string;
};

export function getManualNavItems(input: {
  roles: readonly string[];
  isSuperAdmin: boolean;
  isAuthenticated: boolean;
}): ManualNavItem[] {
  const { roles, isSuperAdmin, isAuthenticated } = input;
  const items: ManualNavItem[] = [];

  if (isSuperAdmin || roles.includes("admin_pays")) {
    items.push({
      toSuffix: "/manual/admin-pays",
      labelKey: "manual.country_admin_nav_title",
      labelDefault: "Manuel admin pays",
      descKey: "manual.country_admin_nav_desc",
      descDefault: "Guide admin pays — commissions et fond de garantie",
    });
  }

  if (isAuthenticated && hasSellerManualAccess(roles)) {
    items.push({
      toSuffix: "/manual/vendeur",
      labelKey: "manual.seller_nav_title",
      labelDefault: "Manuel vendeur",
      descKey: "manual.seller_nav_desc",
      descDefault: "Guichet, caisse, scan et suivi des billets",
    });
  }

  // Restreint aux rôles concernés — jamais de manuel visible pour un
  // visiteur non authentifié ou sans rôle correspondant (aucun repli public).
  const showCompanyManual =
    isAuthenticated &&
    !isSellerOnlyManualProfile(roles, isSuperAdmin) &&
    (isSuperAdmin || roles.includes("owner") || roles.includes("admin_pays"));

  if (showCompanyManual) {
    const hasCompanyManual = items.some((item) => item.toSuffix === "/manual/compagnie");
    if (!hasCompanyManual) {
      items.push({
        toSuffix: "/manual/compagnie",
        labelKey: "manual.nav_title",
        labelDefault: "Manuel compagnie",
        descKey: "manual.nav_desc",
        descDefault: "Guide complet pour former vos équipes",
      });
    }
  }

  return items;
}
