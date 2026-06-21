import type { LucideIcon } from "lucide-react";
import {
  BarChart3Icon,
  BuildingIcon,
  BusIcon,
  CalendarIcon,
  FileSpreadsheetIcon,
  LandmarkIcon,
  MapPinIcon,
  MessageSquareIcon,
  PackageIcon,
  PercentIcon,
  ReceiptTextIcon,
  RouteIcon,
  ScanLineIcon,
  ShieldIcon,
  StoreIcon,
  TagIcon,
  TicketIcon,
  WalletIcon,
  HandCoinsIcon,
  PlugIcon,
  UsersIcon,
} from "lucide-react";
import {
  companyModuleEnabled,
  type CompanyFeatureModules,
} from "@/lib/company-feature-modules.ts";
import { OWNER_CONSOLE_MODULE_FEATURE, OWNER_NAV_SUFFIX_FEATURE } from "@/lib/company-feature-module-map.ts";

export const GUARANTEE_FUND_ACCESS_ROLES = [
  "owner",
  "comptable_compagnie",
  "super_admin",
] as const;

/** Rôles avec accès console compagnie (/owner) au-delà du seul owner. */
export const COMPANY_CONSOLE_ROLE_NAMES = [
  "owner",
  "comptable_compagnie",
  "controleur",
  "gerant_gare",
  "gestionnaire_gare",
  "controleur_gare",
  "comptable_gare",
] as const;

export const GARE_MANAGER_CONSOLE_ROLE_NAMES = ["gerant_gare", "gestionnaire_gare"] as const;

/** Roles with access to the counter / vendor card (`/seller`). */
export const VENDOR_CONSOLE_ROLE_NAMES = [
  "owner",
  "vendeur",
  "vendeur_gare",
  "chauffeur",
  "vendeur_reseau",
  "vendeur_master",
  "controleur",
  "super_admin",
] as const;

export function canReprintCounterTickets(roles: string[], isSuperAdmin = false): boolean {
  if (isSuperAdmin) return true;
  return VENDOR_CONSOLE_ROLE_NAMES.some((role) => roles.includes(role));
}

export function canAccessGuaranteeFund(roles: string[], isSuperAdmin: boolean): boolean {
  if (isSuperAdmin) return true;
  return GUARANTEE_FUND_ACCESS_ROLES.some((role) => roles.includes(role));
}

export type OwnerConsoleModule = {
  id: string;
  titleKey: string;
  descKey: string;
  titleDefault: string;
  descDefault: string;
  toSuffix: string;
  icon: LucideIcon;
  /** Empty = visible to any owner-staff role */
  roles?: string[];
  /** Shown only to super_admin */
  adminOnly?: boolean;
  /** data-tour target for guided tour on owner overview */
  tourTarget?: string;
  sectionKey: string;
  sectionDefault: string;
};

export const OWNER_CONSOLE_MODULES: OwnerConsoleModule[] = [
  {
    id: "sales",
    sectionKey: "console.section_commercial",
    sectionDefault: "Commercial & ventes",
    titleKey: "console.sales_title",
    titleDefault: "Journal des ventes",
    descKey: "console.sales_desc",
    descDefault: "Billets vendus, annulations et réimpressions.",
    toSuffix: "/owner/sales",
    icon: ReceiptTextIcon,
    tourTarget: "owner-sales",
  },
  {
    id: "seller",
    sectionKey: "console.section_commercial",
    sectionDefault: "Commercial & ventes",
    titleKey: "console.seller_title",
    titleDefault: "Billetterie guichet",
    descKey: "console.seller_desc",
    descDefault: "Vente, réservation et consultation des tickets.",
    toSuffix: "/seller",
    icon: TicketIcon,
    roles: ["owner", "vendeur", "chauffeur", "vendeur_reseau", "vendeur_master", "controleur", "super_admin"],
  },
  {
    id: "promo",
    sectionKey: "console.section_commercial",
    sectionDefault: "Commercial & ventes",
    titleKey: "console.promo_title",
    titleDefault: "Codes promo",
    descKey: "console.promo_desc",
    descDefault: "Réductions et campagnes promotionnelles.",
    toSuffix: "/owner/promo-codes",
    icon: TagIcon,
    tourTarget: "owner-promo-codes",
  },
  {
    id: "loyalty",
    sectionKey: "console.section_commercial",
    sectionDefault: "Commercial & ventes",
    titleKey: "console.loyalty_title",
    titleDefault: "Fidélité compagnie",
    descKey: "console.loyalty_desc",
    descDefault: "Points et avantages pour vos voyageurs.",
    toSuffix: "/owner/loyalty",
    icon: PercentIcon,
    tourTarget: "owner-loyalty",
  },
  {
    id: "guarantee",
    sectionKey: "console.section_finance",
    sectionDefault: "Finance & garantie",
    titleKey: "console.guarantee_title",
    titleDefault: "Fond de garantie",
    descKey: "console.guarantee_desc",
    descDefault: "Solde, dépôts plateforme et validation comptable.",
    toSuffix: "/owner/guarantee-fund",
    icon: LandmarkIcon,
    roles: [...GUARANTEE_FUND_ACCESS_ROLES],
    tourTarget: "owner-guarantee-fund",
  },
  {
    id: "cash",
    sectionKey: "console.section_finance",
    sectionDefault: "Finance & garantie",
    titleKey: "console.cash_title",
    titleDefault: "Caisse gare",
    descKey: "console.cash_desc",
    descDefault: "Caisses ouvertes, mouvements et reversements.",
    toSuffix: "/owner/cash-register",
    icon: WalletIcon,
    roles: ["owner", "comptable_compagnie", "super_admin"],
    tourTarget: "owner-cash-register",
  },
  {
    id: "counter-commissions",
    sectionKey: "console.section_finance",
    sectionDefault: "Finance & garantie",
    titleKey: "console.counter_commissions_title",
    titleDefault: "Commissions guichet",
    descKey: "console.counter_commissions_desc",
    descDefault: "Tranches fixe ou % pour vendeurs au guichet.",
    toSuffix: "/owner/counter-commissions",
    icon: PercentIcon,
    roles: ["owner", "comptable_compagnie", "super_admin"],
    tourTarget: "owner-counter-commissions",
  },
  {
    id: "gare-manager-commissions",
    sectionKey: "console.section_finance",
    sectionDefault: "Finance & garantie",
    titleKey: "console.gare_manager_commissions_title",
    titleDefault: "Commissions gestionnaires",
    descKey: "console.gare_manager_commissions_desc",
    descDefault: "Parts des chefs de gare : perçu au guichet et réservations à reverser.",
    toSuffix: "/owner/gare-manager-commissions",
    icon: HandCoinsIcon,
    roles: ["owner", "comptable_compagnie", "super_admin"],
    tourTarget: "owner-gare-commissions",
  },
  {
    id: "expenses",
    sectionKey: "console.section_finance",
    sectionDefault: "Finance & garantie",
    titleKey: "console.expenses_title",
    titleDefault: "Dépenses",
    descKey: "console.expenses_desc",
    descDefault: "Saisie des charges par type, imputées à l'équipe ou à un bus rattaché à une gare.",
    toSuffix: "/owner/expenses",
    icon: ReceiptTextIcon,
    roles: ["owner", "comptable_compagnie", "super_admin"],
    tourTarget: "owner-expenses",
  },
  {
    id: "income-statement",
    sectionKey: "console.section_finance",
    sectionDefault: "Finance & garantie",
    titleKey: "console.income_statement_title",
    titleDefault: "Compte de résultat",
    descKey: "console.income_statement_desc",
    descDefault: "Bilan périodique SYSCOHADA : produits, charges et résultat net.",
    toSuffix: "/owner/income-statement",
    icon: FileSpreadsheetIcon,
    roles: ["owner", "comptable_compagnie", "super_admin"],
    tourTarget: "owner-income-statement",
  },
  {
    id: "analytics",
    sectionKey: "console.section_finance",
    sectionDefault: "Finance & garantie",
    titleKey: "console.analytics_title",
    titleDefault: "Analyses comptables",
    descKey: "console.analytics_desc",
    descDefault: "Revenus, caisse, commissions et KPI.",
    toSuffix: "/owner/analytics",
    icon: BarChart3Icon,
    tourTarget: "owner-analytics",
  },
  {
    id: "fleet",
    sectionKey: "console.section_operations",
    sectionDefault: "Exploitation",
    titleKey: "console.fleet_title",
    titleDefault: "Flotte",
    descKey: "console.fleet_desc",
    descDefault: "Bus, immatriculation et capacité des véhicules.",
    toSuffix: "/owner/buses",
    icon: BusIcon,
    tourTarget: "owner-fleet",
  },
  {
    id: "stations",
    sectionKey: "console.section_operations",
    sectionDefault: "Exploitation",
    titleKey: "console.stations_title",
    titleDefault: "Gares",
    descKey: "console.stations_desc",
    descDefault: "Points d'arrêt, villes et gestionnaires de gare.",
    toSuffix: "/owner/stations",
    icon: MapPinIcon,
    tourTarget: "owner-stations",
    roles: ["owner", "super_admin"],
  },
  {
    id: "gare-dashboard",
    sectionKey: "console.section_operations",
    sectionDefault: "Exploitation",
    titleKey: "console.gare_dashboard_title",
    titleDefault: "Ma gare",
    descKey: "console.gare_dashboard_desc",
    descDefault: "Équipe de gare, commissions guichet et accès voyages.",
    toSuffix: "/owner/gare-dashboard",
    icon: MapPinIcon,
    roles: [...GARE_MANAGER_CONSOLE_ROLE_NAMES],
    tourTarget: "owner-gare-dashboard",
  },
  {
    id: "routes",
    sectionKey: "console.section_operations",
    sectionDefault: "Exploitation",
    titleKey: "console.routes_title",
    titleDefault: "Itinéraires",
    descKey: "console.routes_desc",
    descDefault: "Lignes, tarifs et gares de départ et d'arrivée.",
    toSuffix: "/owner/routes",
    icon: RouteIcon,
    tourTarget: "owner-routes",
    roles: ["owner", "comptable_compagnie", "controleur", ...GARE_MANAGER_CONSOLE_ROLE_NAMES, "controleur_gare", "comptable_gare", "super_admin"],
  },
  {
    id: "team",
    sectionKey: "console.section_operations",
    sectionDefault: "Exploitation",
    titleKey: "console.team_title",
    titleDefault: "Équipe",
    descKey: "console.team_desc",
    descDefault: "Créer des comptes et attribuer vendeur, comptable, contrôleur ou gestionnaire de gare.",
    toSuffix: "/owner/sellers",
    icon: UsersIcon,
    roles: ["owner", "super_admin"],
    tourTarget: "owner-sellers",
  },
  {
    id: "trips",
    sectionKey: "console.section_operations",
    sectionDefault: "Exploitation",
    titleKey: "console.trips_title",
    titleDefault: "Voyages & départs",
    descKey: "console.trips_desc",
    descDefault: "Planification des trajets et des départs.",
    toSuffix: "/owner/trips",
    icon: CalendarIcon,
    tourTarget: "owner-trips",
    roles: ["owner", "comptable_compagnie", "controleur", ...GARE_MANAGER_CONSOLE_ROLE_NAMES, "controleur_gare", "comptable_gare", "super_admin"],
  },
  {
    id: "partner-api",
    sectionKey: "console.section_operations",
    sectionDefault: "Exploitation",
    titleKey: "console.partner_api_title",
    titleDefault: "API partenaire",
    descKey: "console.partner_api_desc",
    descDefault: "Lier les itinéraires d'un système externe et exposer les places disponibles.",
    toSuffix: "/owner/partner-api",
    icon: PlugIcon,
    roles: ["owner", "super_admin"],
    tourTarget: "owner-partner-api",
  },
  {
    id: "colis",
    sectionKey: "console.section_operations",
    sectionDefault: "Exploitation",
    titleKey: "console.colis_title",
    titleDefault: "Colis autonomes",
    descKey: "console.colis_desc",
    descDefault: "Nature de colis, SMS et paramètres module.",
    toSuffix: "/owner/colis",
    icon: PackageIcon,
    tourTarget: "owner-colis",
  },
  {
    id: "scan",
    sectionKey: "console.section_operations",
    sectionDefault: "Exploitation",
    titleKey: "console.scan_title",
    titleDefault: "Contrôle embarquement",
    descKey: "console.scan_desc",
    descDefault: "Scanner QR et validation des billets.",
    toSuffix: "/verify/scan",
    icon: ScanLineIcon,
    roles: ["owner", "controleur", "vendeur", "chauffeur", "vendeur_reseau", "vendeur_master", "super_admin"],
    tourTarget: "owner-scan",
  },
  {
    id: "company",
    sectionKey: "console.section_settings",
    sectionDefault: "Paramètres",
    titleKey: "console.company_title",
    titleDefault: "Mon entreprise",
    descKey: "console.company_desc",
    descDefault: "Profil public, logo et coordonnées.",
    toSuffix: "/owner/company",
    icon: BuildingIcon,
    tourTarget: "owner-company",
  },
  {
    id: "cancellation",
    sectionKey: "console.section_settings",
    sectionDefault: "Paramètres",
    titleKey: "console.cancellation_title",
    titleDefault: "Politique d'annulation",
    descKey: "console.cancellation_desc",
    descDefault: "Frais, délais et règles de remboursement.",
    toSuffix: "/owner/cancellation",
    icon: ReceiptTextIcon,
    tourTarget: "owner-cancellation",
  },
  {
    id: "messages",
    sectionKey: "console.section_settings",
    sectionDefault: "Paramètres",
    titleKey: "console.messages_title",
    titleDefault: "Messages & contact",
    descKey: "console.messages_desc",
    descDefault: "WhatsApp, email de notification et support.",
    toSuffix: "/owner/messages",
    icon: MessageSquareIcon,
    tourTarget: "owner-messages",
  },
  {
    id: "admin",
    sectionKey: "console.section_admin",
    sectionDefault: "Administration plateforme",
    titleKey: "console.admin_title",
    titleDefault: "Console super admin",
    descKey: "console.admin_desc",
    descDefault: "Utilisateurs, compagnies, fonds garantie plateforme.",
    toSuffix: "/admin",
    icon: ShieldIcon,
    adminOnly: true,
  },
  {
    id: "become-owner-hub",
    sectionKey: "console.section_admin",
    sectionDefault: "Administration plateforme",
    titleKey: "console.companies_title",
    titleDefault: "Compagnies de transport",
    descKey: "console.companies_desc",
    descDefault: "Créer une compagnie et désigner son propriétaire.",
    toSuffix: "/admin",
    icon: StoreIcon,
    adminOnly: true,
  },
];

export function filterOwnerConsoleModules(
  roles: string[],
  isSuperAdmin: boolean,
  featureModules?: CompanyFeatureModules | null,
): OwnerConsoleModule[] {
  return OWNER_CONSOLE_MODULES.filter((module) => {
    if (module.adminOnly) return isSuperAdmin;
    if (module.roles && module.roles.length > 0) {
      if (!module.roles.some((role) => roles.includes(role))) return false;
    } else if (
      !roles.includes("owner") &&
      !roles.includes("comptable_compagnie") &&
      !roles.includes("controleur") &&
      !isSuperAdmin
    ) {
      return false;
    }

    if (featureModules) {
      const commercialModule = OWNER_CONSOLE_MODULE_FEATURE[module.id];
      if (commercialModule && !companyModuleEnabled(featureModules, commercialModule)) {
        return false;
      }
    }

    return true;
  });
}

export function isOwnerNavPathEnabled(
  toSuffix: string,
  featureModules?: CompanyFeatureModules | null,
): boolean {
  if (!featureModules) return true;
  const commercialModule = OWNER_NAV_SUFFIX_FEATURE[toSuffix];
  if (!commercialModule) return true;
  return companyModuleEnabled(featureModules, commercialModule);
}

export function groupOwnerConsoleModules(
  modules: OwnerConsoleModule[],
): Array<{ sectionKey: string; sectionDefault: string; items: OwnerConsoleModule[] }> {
  const sections = new Map<
    string,
    { sectionKey: string; sectionDefault: string; items: OwnerConsoleModule[] }
  >();

  for (const module of modules) {
    const existing = sections.get(module.sectionKey);
    if (existing) {
      existing.items.push(module);
    } else {
      sections.set(module.sectionKey, {
        sectionKey: module.sectionKey,
        sectionDefault: module.sectionDefault,
        items: [module],
      });
    }
  }

  return Array.from(sections.values());
}
