// Registre central de tous les droits (Role.droits) connus de la
// plateforme. Sert à afficher/éditer les permissions par rôle dans l'écran
// admin "Rôles & Permissions" (SupabaseAdminPanel.tsx, onglet "roles").
//
// "wired" indique si ce droit est réellement consulté quelque part dans le
// code (front hasDroit() et/ou RLS has_company_droit/has_country_droit côté
// base) — les droits non "wired" sont purement informatifs pour l'instant :
// les cocher/décocher ici ne change aucun comportement observable ailleurs
// dans l'app, seulement l'affichage sur cette page. On l'affiche pour que le
// super_admin ne soit pas surpris par un toggle sans effet.
export type DroitDefinition = {
  key: string;
  labelKey: string;
  descKey: string;
  wired: boolean;
};

export const DROIT_REGISTRY: DroitDefinition[] = [
  { key: "manage_platform", labelKey: "manage_platform", descKey: "manage_platform_desc", wired: false },
  { key: "manage_roles", labelKey: "manage_roles", descKey: "manage_roles_desc", wired: false },
  { key: "manage_country", labelKey: "manage_country", descKey: "manage_country_desc", wired: false },
  { key: "manage_geography", labelKey: "manage_geography", descKey: "manage_geography_desc", wired: true },
  { key: "manage_company", labelKey: "manage_company", descKey: "manage_company_desc", wired: false },
  { key: "manage_feature_modules", labelKey: "manage_feature_modules", descKey: "manage_feature_modules_desc", wired: true },
  { key: "manage_buses", labelKey: "manage_buses", descKey: "manage_buses_desc", wired: false },
  { key: "manage_stations", labelKey: "manage_stations", descKey: "manage_stations_desc", wired: false },
  { key: "manage_gare", labelKey: "manage_gare", descKey: "manage_gare_desc", wired: false },
  { key: "manage_routes", labelKey: "manage_routes", descKey: "manage_routes_desc", wired: false },
  { key: "manage_trips", labelKey: "manage_trips", descKey: "manage_trips_desc", wired: false },
  { key: "schedule_trips", labelKey: "schedule_trips", descKey: "schedule_trips_desc", wired: false },
  { key: "sell_tickets", labelKey: "sell_tickets", descKey: "sell_tickets_desc", wired: false },
  { key: "sell_all_companies", labelKey: "sell_all_companies", descKey: "sell_all_companies_desc", wired: false },
  { key: "reserve_tickets", labelKey: "reserve_tickets", descKey: "reserve_tickets_desc", wired: false },
  { key: "view_bookings", labelKey: "view_bookings", descKey: "view_bookings_desc", wired: false },
  { key: "cancel_bookings", labelKey: "cancel_bookings", descKey: "cancel_bookings_desc", wired: false },
  { key: "control_tickets", labelKey: "control_tickets", descKey: "control_tickets_desc", wired: false },
  { key: "manage_sellers", labelKey: "manage_sellers", descKey: "manage_sellers_desc", wired: false },
  { key: "manage_independent_sellers", labelKey: "manage_independent_sellers", descKey: "manage_independent_sellers_desc", wired: false },
  { key: "manage_network_sellers", labelKey: "manage_network_sellers", descKey: "manage_network_sellers_desc", wired: false },
  { key: "view_network_commissions", labelKey: "view_network_commissions", descKey: "view_network_commissions_desc", wired: false },
  { key: "view_recruited_companies", labelKey: "view_recruited_companies", descKey: "view_recruited_companies_desc", wired: false },
  { key: "view_recruiter_commissions", labelKey: "view_recruiter_commissions", descKey: "view_recruiter_commissions_desc", wired: false },
  { key: "view_reports", labelKey: "view_reports", descKey: "view_reports_desc", wired: false },
  { key: "view_accounting", labelKey: "view_accounting", descKey: "view_accounting_desc", wired: false },
  { key: "manage_accounting", labelKey: "manage_accounting", descKey: "manage_accounting_desc", wired: false },
  { key: "manage_subscriptions", labelKey: "manage_subscriptions", descKey: "manage_subscriptions_desc", wired: false },
  { key: "assign_company_roles", labelKey: "assign_company_roles", descKey: "assign_company_roles_desc", wired: false },
];

export const DROIT_KEYS = DROIT_REGISTRY.map((d) => d.key);

export function isKnownDroit(key: string): boolean {
  return DROIT_KEYS.includes(key);
}
