import type { LucideIcon } from "lucide-react";
import {
  BarChart3Icon,
  BuildingIcon,
  CalendarIcon,
  LandmarkIcon,
  MessageSquareIcon,
  PackageIcon,
  PercentIcon,
  ReceiptTextIcon,
  ScanLineIcon,
  ShieldIcon,
  StoreIcon,
  TagIcon,
  TicketIcon,
  WalletIcon,
} from "lucide-react";

export const GUARANTEE_FUND_ACCESS_ROLES = [
  "owner",
  "comptable_compagnie",
  "super_admin",
] as const;

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
    roles: ["owner", "vendeur", "vendeur_reseau", "vendeur_master", "controleur", "super_admin"],
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
    roles: ["owner", "controleur", "vendeur", "vendeur_reseau", "vendeur_master", "super_admin"],
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
): OwnerConsoleModule[] {
  return OWNER_CONSOLE_MODULES.filter((module) => {
    if (module.adminOnly) return isSuperAdmin;
    if (module.roles && module.roles.length > 0) {
      return module.roles.some((role) => roles.includes(role));
    }
    return roles.includes("owner") || roles.includes("comptable_compagnie") || isSuperAdmin;
  });
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
