export type AdminPanelTabId =
  | "users"
  | "companies"
  | "subscriptions"
  | "plans"
  | "commissions"
  | "guarantee_fund"
  | "geography"
  | "roles"
  | "contact"
  | "loyalty"
  | "legal"
  | "scaling_metrics"
  | "landing";

/** Suffix `.*` loads logs whose moduleKey starts with the prefix (commissions sub-modules). */
export const ADMIN_TAB_AUDIT_MODULE_KEYS: Record<AdminPanelTabId, string> = {
  users: "admin.users",
  companies: "admin.companies",
  subscriptions: "admin.subscriptions",
  plans: "admin.plans",
  commissions: "admin.commissions.*",
  guarantee_fund: "admin.guarantee_fund",
  geography: "admin.geography",
  roles: "admin.roles",
  contact: "admin.contact",
  loyalty: "admin.loyalty",
  legal: "admin.legal",
  scaling_metrics: "admin.scaling_metrics",
  landing: "admin.landing",
};

export function auditModuleKeyMatchesFilter(filterKey: string, loggedKey: string): boolean {
  if (filterKey.endsWith(".*")) {
    return loggedKey.startsWith(filterKey.slice(0, -2));
  }
  return loggedKey === filterKey;
}
