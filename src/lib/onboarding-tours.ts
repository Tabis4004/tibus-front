import type { OnboardingAudience } from "@/lib/onboarding-audience.ts";
import { OWNER_CONSOLE_MODULES } from "@/lib/owner-console-modules.tsx";

export type TourStepConfig = {
  target: string;
  titleKey: string;
  descKey: string;
  titleDefault: string;
  descDefault: string;
  placement?: "top" | "bottom" | "left" | "right";
};

export type ResolvedTour = {
  steps: TourStepConfig[];
  onStart?: () => void;
};

export function buildOwnerOverviewTourSteps(): TourStepConfig[] {
  const moduleSteps: TourStepConfig[] = OWNER_CONSOLE_MODULES.filter(
    (module) => module.tourTarget,
  ).map((module) => ({
    target: `[data-tour="${module.tourTarget}"]`,
    titleKey: module.titleKey,
    descKey: module.descKey,
    titleDefault: module.titleDefault,
    descDefault: module.descDefault,
    placement: "bottom" as const,
  }));

  return [
    {
      target: '[data-tour="owner-explore-features"]',
      titleKey: "tour.owner.explore_title",
      descKey: "tour.owner.explore_desc",
      titleDefault: "Explorer à tout moment",
      descDefault:
        "Relancez ce guide via ce bouton, le header (après le drapeau) ou le menu utilisateur.",
      placement: "bottom",
    },
    {
      target: '[data-tour="owner-overview"]',
      titleKey: "tour.owner.overview_title",
      descKey: "tour.owner.overview_desc",
      titleDefault: "Aperçu",
      descDefault: "Indicateurs clés et accès rapide par blocs à votre activité.",
      placement: "bottom",
    },
    ...moduleSteps,
  ];
}

export const OWNER_SIDEBAR_TOUR: TourStepConfig[] = [
  {
    target: '[data-tour="owner-explore-features"]',
    titleKey: "tour.owner.explore_title",
    descKey: "tour.owner.explore_desc",
    titleDefault: "Explorer à tout moment",
    descDefault:
      "Relancez ce guide quand vous voulez via ce bouton, le header ou le menu utilisateur.",
    placement: "right",
  },
  {
    target: '[data-tour="owner-overview"]',
    titleKey: "tour.owner.overview_title",
    descKey: "tour.owner.overview_desc",
    titleDefault: "Aperçu",
    descDefault: "Tableau de bord : indicateurs clés et accès rapides à votre activité.",
    placement: "right",
  },
  {
    target: '[data-tour="owner-company"]',
    titleKey: "tour.owner.company_title",
    descKey: "tour.owner.company_desc",
    titleDefault: "Mon entreprise",
    descDefault: "CRUD du profil compagnie : nom, logo, coordonnées et informations légales.",
    placement: "right",
  },
  {
    target: '[data-tour="owner-reviews"]',
    titleKey: "tour.owner.reviews_title",
    descKey: "tour.owner.reviews_desc",
    titleDefault: "Avis voyageurs",
    descDefault: "Consultez et répondez aux avis laissés par vos clients.",
    placement: "right",
  },
  {
    target: '[data-tour="owner-promo-codes"]',
    titleKey: "tour.owner.promo_title",
    descKey: "tour.owner.promo_desc",
    titleDefault: "Codes promo",
    descDefault: "Créez, modifiez et désactivez des codes de réduction.",
    placement: "right",
  },
  {
    target: '[data-tour="owner-subscription"]',
    titleKey: "tour.owner.subscription_title",
    descKey: "tour.owner.subscription_desc",
    titleDefault: "Abonnement",
    descDefault: "Gérez votre formule Tibus et le statut de votre abonnement.",
    placement: "right",
  },
  {
    target: '[data-tour="owner-analytics"]',
    titleKey: "tour.owner.analytics_title",
    descKey: "tour.owner.analytics_desc",
    titleDefault: "Analyses",
    descDefault: "Vue synthétique : revenus, réservations et performances.",
    placement: "right",
  },
  {
    target: '[data-tour="owner-ticket-reports"]',
    titleKey: "tour.owner.ticket_reports_title",
    descKey: "tour.owner.ticket_reports_desc",
    titleDefault: "Rapports billets",
    descDefault: "Détail des ventes de billets par période, trajet et canal.",
    placement: "right",
  },
  {
    target: '[data-tour="owner-trip-reports"]',
    titleKey: "tour.owner.trip_reports_title",
    descKey: "tour.owner.trip_reports_desc",
    titleDefault: "Rapports voyages",
    descDefault: "Suivez l'occupation et les performances de chaque départ.",
    placement: "right",
  },
  {
    target: '[data-tour="owner-travelers"]',
    titleKey: "tour.owner.travelers_title",
    descKey: "tour.owner.travelers_desc",
    titleDefault: "Voyageurs",
    descDefault: "Analysez vos clients récurrents et leur historique.",
    placement: "right",
  },
  {
    target: '[data-tour="owner-sales"]',
    titleKey: "tour.owner.sales_title",
    descKey: "tour.owner.sales_desc",
    titleDefault: "Journal des ventes",
    descDefault: "Liste complète des ventes guichet et en ligne avec filtres.",
    placement: "right",
  },
  {
    target: '[data-tour="owner-cash-register"]',
    titleKey: "tour.owner.cash_title",
    descKey: "tour.owner.cash_desc",
    titleDefault: "Caisse guichet",
    descDefault: "Suivez les sessions caisse et validez les reversements vendeurs.",
    placement: "right",
  },
  {
    target: '[data-tour="owner-messages"]',
    titleKey: "tour.owner.messages_title",
    descKey: "tour.owner.messages_desc",
    titleDefault: "Contact",
    descDefault: "Paramétrez WhatsApp et les canaux de contact voyageurs.",
    placement: "right",
  },
  {
    target: '[data-tour="owner-loyalty"]',
    titleKey: "tour.owner.loyalty_title",
    descKey: "tour.owner.loyalty_desc",
    titleDefault: "Fidélité",
    descDefault: "Activez le programme points et configurez les règles de gain.",
    placement: "right",
  },
  {
    target: '[data-tour="owner-colis"]',
    titleKey: "tour.owner.colis_title",
    descKey: "tour.owner.colis_desc",
    titleDefault: "Colis autonomes",
    descDefault: "Paramétrez types de colis, tarifs et règles d'expédition.",
    placement: "right",
  },
  {
    target: '[data-tour="owner-guarantee-fund"]',
    titleKey: "tour.owner.guarantee_fund_title",
    descKey: "tour.owner.guarantee_fund_desc",
    titleDefault: "Fond de garantie",
    descDefault: "Consultez et gérez le fond de garantie de votre compagnie.",
    placement: "right",
  },
  {
    target: '[data-tour="owner-cancellation"]',
    titleKey: "tour.owner.cancellation_title",
    descKey: "tour.owner.cancellation_desc",
    titleDefault: "Pénalités annulation",
    descDefault: "Définissez les règles et montants en cas d'annulation.",
    placement: "right",
  },
  {
    target: '[data-tour="owner-fleet"]',
    titleKey: "tour.owner.fleet_title",
    descKey: "tour.owner.fleet_desc",
    titleDefault: "Flotte",
    descDefault: "CRUD bus : capacité, type de véhicule et configuration des sièges.",
    placement: "right",
  },
  {
    target: '[data-tour="owner-stations"]',
    titleKey: "tour.owner.stations_title",
    descKey: "tour.owner.stations_desc",
    titleDefault: "Gares",
    descDefault: "Créez et modifiez vos gares et points d'arrêt.",
    placement: "right",
  },
  {
    target: '[data-tour="owner-routes"]',
    titleKey: "tour.owner.routes_title",
    descKey: "tour.owner.routes_desc",
    titleDefault: "Itinéraires",
    descDefault: "Définissez les lignes, segments et tarifs entre gares.",
    placement: "right",
  },
  {
    target: '[data-tour="owner-trips-shortcut"]',
    titleKey: "tour.owner.trips_shortcut_title",
    descKey: "tour.owner.trips_shortcut_desc",
    titleDefault: "Raccourci voyages",
    descDefault: "Accès rapide à la programmation des départs (mobile).",
    placement: "right",
  },
  {
    target: '[data-tour="owner-trips"]',
    titleKey: "tour.owner.trips_title",
    descKey: "tour.owner.trips_desc",
    titleDefault: "Programmation",
    descDefault: "CRUD voyages : date, heure, prix, bus et ouverture des ventes.",
    placement: "right",
  },
  {
    target: '[data-tour="owner-scan"]',
    titleKey: "tour.owner.scan_title",
    descKey: "tour.owner.scan_desc",
    titleDefault: "Scanner billets",
    descDefault: "Contrôlez l'embarquement en validant les QR codes.",
    placement: "right",
  },
  {
    target: '[data-tour="owner-sellers"]',
    titleKey: "tour.owner.sellers_title",
    descKey: "tour.owner.sellers_desc",
    titleDefault: "Équipe",
    descDefault: "Gérez vendeurs, comptables et contrôleurs : invitation, rôles et accès.",
    placement: "right",
  },
];

/** Tour guichet vendeur — intérieur du dashboard */
export const SELLER_TOUR: TourStepConfig[] = [
  {
    target: '[data-tour="seller-header"]',
    titleKey: "tour.seller.header_title",
    descKey: "tour.seller.header_desc",
    titleDefault: "Espace guichet",
    descDefault:
      "Bienvenue sur votre espace de vente. Tout part d'ici chaque jour.",
    placement: "bottom",
  },
  {
    target: '[data-tour="seller-kpis"]',
    titleKey: "tour.seller.kpis_title",
    descKey: "tour.seller.kpis_desc",
    titleDefault: "Tableau de bord",
    descDefault:
      "Voyez en un coup d'œil le mode caisse, les départs du jour, les places et vos commissions.",
    placement: "bottom",
  },
  {
    target: '[data-tour="seller-commissions"]',
    titleKey: "tour.seller.commissions_title",
    descKey: "tour.seller.commissions_desc",
    titleDefault: "Commissions",
    descDefault:
      "Si vous êtes éligible, suivez ici vos commissions en attente et déjà payées.",
    placement: "bottom",
  },
  {
    target: '[data-tour="seller-cash"]',
    titleKey: "tour.seller.cash_title",
    descKey: "tour.seller.cash_desc",
    titleDefault: "Caisse physique",
    descDefault:
      "Ouvrez votre caisse le matin, encaissez les ventes cash et faites le reversement en fin de service.",
    placement: "bottom",
  },
  {
    target: '[data-tour="seller-departures"]',
    titleKey: "tour.seller.departures_title",
    descKey: "tour.seller.departures_desc",
    titleDefault: "Départs disponibles",
    descDefault:
      "Liste des voyages ouverts à la vente. Choisissez un départ pour émettre des billets.",
    placement: "top",
  },
  {
    target: '[data-tour="seller-sell-trip"]',
    titleKey: "tour.seller.sell_title",
    descKey: "tour.seller.sell_desc",
    titleDefault: "Vente au guichet",
    descDefault:
      "Cliquez ici pour ajouter les voyageurs, choisir les sièges et imprimer le billet.",
    placement: "top",
  },
  {
    target: '[data-tour="seller-scan"]',
    titleKey: "tour.seller.scan_title",
    descKey: "tour.seller.scan_desc",
    titleDefault: "Scanner les billets",
    descDefault:
      "Validez les QR codes à l'embarquement et marquez les passagers à bord.",
    placement: "bottom",
  },
  {
    target: '[data-tour="seller-colis"]',
    titleKey: "tour.seller.colis_title",
    descKey: "tour.seller.colis_desc",
    titleDefault: "Colis autonomes",
    descDefault:
      "Enregistrez, suivez et remettez les colis expédiés depuis votre guichet.",
    placement: "bottom",
  },
];

function isMobileViewport() {
  return window.matchMedia("(max-width: 767px)").matches;
}

export function filterTourSteps(steps: TourStepConfig[]) {
  const mobile = isMobileViewport();
  return steps.filter((step) => {
    if (step.target.includes("owner-trips-shortcut") && !mobile) return false;
    if (step.target === '[data-tour="owner-trips"]' && mobile) return false;
    return Boolean(document.querySelector(step.target));
  });
}

export const TRAVELER_HOME_TOUR: TourStepConfig[] = [
  {
    target: '[data-tour="travel-book"]',
    titleKey: "tour.traveler.book_title",
    descKey: "tour.traveler.book_desc",
    titleDefault: "Réserver",
    descDefault: "Recherchez un trajet et réservez votre place en quelques clics.",
    placement: "bottom",
  },
  {
    target: '[data-tour="travel-referral"]',
    titleKey: "tour.traveler.referral_title",
    descKey: "tour.traveler.referral_desc",
    titleDefault: "Parrainage",
    descDefault: "Gagnez des points Tibus en parrainant vos proches.",
    placement: "bottom",
  },
  {
    target: '[data-tour="travel-guide"]',
    titleKey: "tour.traveler.guide_title",
    descKey: "tour.traveler.guide_desc",
    titleDefault: "Guide",
    descDefault: "Retrouvez à tout moment l'aide détaillée sur Tibus.",
    placement: "bottom",
  },
];

export const OWNER_HOME_TOUR: TourStepConfig[] = [
  {
    target: '[data-tour="home-owner-dashboard"]',
    titleKey: "tour.owner.home_dashboard_title",
    descKey: "tour.owner.home_dashboard_desc",
    titleDefault: "Tableau de bord compagnie",
    descDefault:
      "Ouvrez votre espace owner pour gérer flotte, voyages et ventes.",
    placement: "bottom",
  },
];

/** Tour comptable / contrôleur — espace /company/* */
export const COMPANY_STAFF_TOUR: TourStepConfig[] = [
  {
    target: '[data-tour="company-staff-sales"]',
    titleKey: "tour.company_staff.sales_title",
    descKey: "tour.company_staff.sales_desc",
    titleDefault: "Ventes compagnie",
    descDefault:
      "Consultez toutes les ventes guichet et en ligne de votre compagnie, filtrez par période et exportez si besoin.",
    placement: "bottom",
  },
  {
    target: '[data-tour="company-staff-trips"]',
    titleKey: "tour.company_staff.trips_title",
    descKey: "tour.company_staff.trips_desc",
    titleDefault: "Rapports voyages",
    descDefault:
      "Suivez les départs, taux de remplissage et performances par trajet.",
    placement: "bottom",
  },
  {
    target: '[data-tour="company-staff-cash"]',
    titleKey: "tour.company_staff.cash_title",
    descKey: "tour.company_staff.cash_desc",
    titleDefault: "Validation caisse",
    descDefault:
      "Validez les reversements remis par les vendeurs en fin de service. Vous n'ouvrez pas de caisse guichet.",
    placement: "bottom",
  },
  {
    target: '[data-tour="company-nav-scan"]',
    titleKey: "tour.company_staff.scan_title",
    descKey: "tour.company_staff.scan_desc",
    titleDefault: "Scanner les billets",
    descDefault: "Contrôlez l'embarquement en scannant les QR codes des passagers.",
    placement: "top",
  },
  {
    target: '[data-tour="company-nav-sales"]',
    titleKey: "tour.company_staff.nav_sales_title",
    descKey: "tour.company_staff.nav_sales_desc",
    titleDefault: "Menu Ventes",
    descDefault: "Accédez rapidement au journal des ventes depuis la barre de navigation.",
    placement: "top",
  },
  {
    target: '[data-tour="company-nav-trips"]',
    titleKey: "tour.company_staff.nav_trips_title",
    descKey: "tour.company_staff.nav_trips_desc",
    titleDefault: "Menu Voyages",
    descDefault: "Ouvrez les rapports de voyages et d'occupation.",
    placement: "top",
  },
  {
    target: '[data-tour="company-nav-cash"]',
    titleKey: "tour.company_staff.nav_cash_title",
    descKey: "tour.company_staff.nav_cash_desc",
    titleDefault: "Menu Caisse",
    descDefault: "Validez les reversements des vendeurs depuis ce menu.",
    placement: "top",
  },
];

function isHomePath(pathname: string) {
  return /^\/[^/]+\/?$/.test(pathname);
}

function openOwnerSidebarForTour() {
  window.dispatchEvent(
    new CustomEvent("tibus:owner-sidebar", { detail: { open: true } }),
  );
}

export function getDefaultTourPath(audience: OnboardingAudience, lng: string): string {
  switch (audience) {
    case "owner":
      return `/${lng}/owner`;
    case "seller":
      return `/${lng}/seller`;
    case "company_staff":
      return `/${lng}/company/sales`;
    default:
      return `/${lng}`;
  }
}

export function resolveOnboardingTour(
  pathname: string,
  audience: OnboardingAudience,
): ResolvedTour | null {
  if (audience === "owner") {
    if (/\/owner(\/|$)/.test(pathname)) {
      return {
        steps: buildOwnerOverviewTourSteps(),
        onStart: () => {
          openOwnerSidebarForTour();
        },
      };
    }
    if (isHomePath(pathname)) {
      return { steps: OWNER_HOME_TOUR };
    }
    return null;
  }

  if (audience === "seller") {
    if (/\/seller(\/|$)/.test(pathname)) {
      return { steps: SELLER_TOUR };
    }
    if (isHomePath(pathname)) {
      return {
        steps: [
          {
            target: '[data-tour="home-seller-dashboard"]',
            titleKey: "tour.seller.home_dashboard_title",
            descKey: "tour.seller.home_dashboard_desc",
            titleDefault: "Guichet vendeur",
            descDefault: "Accédez à l'espace vendeur pour émettre les billets.",
            placement: "bottom",
          },
        ],
      };
    }
    return null;
  }

  if (audience === "company_staff") {
    if (/\/company(\/|$)/.test(pathname)) {
      return { steps: COMPANY_STAFF_TOUR };
    }
    if (isHomePath(pathname)) {
      return {
        steps: [
          {
            target: '[data-tour="company-staff-home"]',
            titleKey: "tour.company_staff.home_title",
            descKey: "tour.company_staff.home_desc",
            titleDefault: "Espace équipe compagnie",
            descDefault:
              "Accédez aux ventes, rapports voyages et validation des reversements caisse.",
            placement: "bottom",
          },
        ],
      };
    }
    return null;
  }

  if (isHomePath(pathname)) {
    return { steps: TRAVELER_HOME_TOUR };
  }

  return null;
}
