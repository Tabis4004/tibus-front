export type ManualNavItem = {
  toSuffix: string;
  labelKey: string;
  labelDefault: string;
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
    });
  }

  if (!isAuthenticated || isSuperAdmin || roles.includes("owner") || roles.includes("admin_pays")) {
    const hasCompanyManual = items.some((item) => item.toSuffix === "/manual/compagnie");
    if (!hasCompanyManual) {
      items.push({
        toSuffix: "/manual/compagnie",
        labelKey: "manual.nav_title",
        labelDefault: "Manuel compagnie",
      });
    }
  }

  if (items.length === 0) {
    items.push({
      toSuffix: "/manual/compagnie",
      labelKey: "manual.nav_title",
      labelDefault: "Manuel compagnie",
    });
  }

  return items;
}
