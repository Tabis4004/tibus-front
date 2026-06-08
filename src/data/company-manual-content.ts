export type ManualFigure = {
  src: string;
  caption: string;
};

export type ManualSubsection = {
  title: string;
  body: string;
  bullets?: string[];
  figure?: ManualFigure;
};

export type ManualSection = {
  id: string;
  title: string;
  intro?: string;
  paragraphs?: string[];
  bullets?: string[];
  numbered?: string[];
  figure?: ManualFigure;
  subsections?: ManualSubsection[];
};

export const COMPANY_MANUAL_TITLE = "Manuel d'utilisation Tibus";
export const COMPANY_MANUAL_SUBTITLE =
  "Guide compagnie de transport — gérants et super administrateurs";

export const OWNER_MENU_FICHES: ManualSubsection[] = [
  {
    title: "Aperçu",
    body: "Tableau de bord : indicateurs ventes, réservations, occupation. Point de départ chaque journée.",
    figure: {
      src: "/manuel/captures/owner-real-overview.png",
      caption: "Aperçu Owner — console opérationnelle (capture réelle)",
    },
  },
  {
    title: "Mon entreprise",
    body: "Profil public : nom, logo, description, téléphone, e-mail, site web.",
    figure: {
      src: "/manuel/captures/owner-real-company.png",
      caption: "Paramètres de la compagnie",
    },
  },
  {
    title: "Avis",
    body: "Lire et répondre aux avis laissés par les voyageurs.",
    figure: { src: "/manuel/captures/owner-real-reviews.png", caption: "Modération des avis" },
  },
  {
    title: "Codes promo",
    body: "Créer des codes de réduction (% ou montant fixe), dates de validité, limite d'usage.",
    figure: { src: "/manuel/captures/owner-real-promo-codes.png", caption: "Codes promotionnels" },
  },
  {
    title: "Abonnement",
    body: "Formule Tibus active, renouvellement et statut.",
    figure: { src: "/manuel/captures/owner-real-subscription.png", caption: "Plans d'abonnement" },
  },
  {
    title: "Analyses",
    body: "Vue synthétique revenus, réservations et tendances.",
    figure: { src: "/manuel/captures/owner-real-analytics.png", caption: "Tableau de bord analytique" },
  },
  {
    title: "Rapports Billets",
    body: "Détail des ventes par période, trajet et canal (guichet / en ligne).",
    figure: {
      src: "/manuel/captures/owner-real-analytics-tickets.png",
      caption: "Rapports billets",
    },
  },
  {
    title: "Rapports Voyages",
    body: "Occupation et performance de chaque départ programmé.",
    figure: {
      src: "/manuel/captures/owner-real-analytics-trips.png",
      caption: "Rapports voyages",
    },
  },
  {
    title: "Voyageurs",
    body: "Clients récurrents et historique d'achats.",
    figure: {
      src: "/manuel/captures/owner-real-analytics-travelers.png",
      caption: "Base voyageurs",
    },
  },
  {
    title: "Journal des ventes",
    body: "Liste complète des transactions avec filtres et annulations.",
    figure: { src: "/manuel/captures/owner-real-sales.png", caption: "Journal des ventes" },
  },
  {
    title: "Caisse guichet",
    body: "Suivi des sessions caisse vendeurs et reversements.",
    figure: {
      src: "/manuel/captures/owner-real-cash-register.png",
      caption: "Supervision caisse guichet",
    },
  },
  {
    title: "Contact",
    body: "Numéros WhatsApp et canaux visibles par les voyageurs.",
    figure: { src: "/manuel/captures/owner-real-messages.png", caption: "Paramètres contact" },
  },
  {
    title: "Fidélité",
    body: "Programme points compagnie : règles, activation, suivi.",
    figure: { src: "/manuel/captures/owner-real-loyalty.png", caption: "Fidélité compagnie" },
  },
  {
    title: "Colis autonomes",
    body: "Module colis sans billet : enregistrement et suivi.",
    figure: { src: "/manuel/captures/owner-real-colis.png", caption: "Colis autonomes" },
  },
  {
    title: "Fond de garantie",
    body: "Solde garantie pour sécuriser les réservations en ligne. Recharge et suivi des retenues.",
    figure: {
      src: "/manuel/captures/owner-real-guarantee-fund.png",
      caption: "Fond de garantie compagnie",
    },
  },
  {
    title: "Pénalités annulation",
    body: "Règles de remboursement et pénalités.",
    figure: {
      src: "/manuel/captures/owner-real-cancellation-policy.png",
      caption: "Politique d'annulation",
    },
  },
  {
    title: "Flotte",
    body: "Bus : immatriculation, capacité, type.",
    figure: { src: "/manuel/captures/owner-real-buses.png", caption: "Gestion de la flotte" },
  },
  {
    title: "Gares",
    body: "Points d'arrêt et villes desservies.",
    figure: { src: "/manuel/captures/owner-real-stations.png", caption: "Gares et villes" },
  },
  {
    title: "Itinéraires",
    body: "Liaisons gare à gare avec tarifs et kilométrage.",
    figure: { src: "/manuel/captures/owner-real-routes.png", caption: "Itinéraires et tarifs" },
  },
  {
    title: "Voyages",
    body: "Programmation des départs (date, heure, bus, capacité).",
    figure: { src: "/manuel/captures/owner-real-trips.png", caption: "Programmation des voyages" },
  },
  {
    title: "Scanner billets",
    body: "Contrôle QR à l'embarquement.",
    figure: { src: "/manuel/captures/owner-real-scan.png", caption: "Scanner embarquement" },
  },
  {
    title: "Équipe",
    body: "Inviter vendeurs, comptables, contrôleurs ; attribuer les rôles par e-mail.",
    figure: { src: "/manuel/captures/owner-real-sellers.png", caption: "Gestion de l'équipe" },
  },
];

export const COMPANY_MANUAL_SECTIONS: ManualSection[] = [
  {
    id: "roles",
    title: "1. Les quatre rôles principaux",
    bullets: [
      "Owner (gérant) — Configuration complète de la compagnie, flotte, voyages, équipe et pilotage.",
      "Vendeur (guichet) — Vente de billets cash, caisse journalière, scan embarquement, colis.",
      "Équipe compagnie (comptable / contrôleur) — Suivi des ventes, rapports voyages, validation des reversements caisse.",
      "Voyageur — Recherche, réservation en ligne, paiement Mobile Money, billet QR.",
    ],
  },
  {
    id: "owner",
    title: "2. Owner — Gérant de la compagnie",
    intro: "Accès : menu latéral sur /fr/owner (desktop) ou menu hamburger (mobile).",
    figure: {
      src: "/manuel/assets/fig-owner.png",
      caption: "Figure 1 — Navigation Owner et tableau de bord",
    },
    paragraphs: [
      "L'Owner configure l'offre, pilote la performance et invite son équipe. Le sélecteur de compagnie en haut du menu permet de gérer plusieurs compagnies dans différents pays.",
    ],
    subsections: OWNER_MENU_FICHES,
  },
  {
    id: "seller",
    title: "3. Vendeur — Guichet",
    intro: "Accès : /fr/seller · Barre mobile : Accueil · Scanner · Guichet",
    figure: {
      src: "/manuel/assets/fig-vendeur.png",
      caption: "Figure 2 — Espace vendeur : caisse et vente",
    },
    subsections: [
      {
        title: "Ouvrir la caisse",
        body: "Chaque matin : « Session caisse journalière » avec fond de roulement (souvent 0). Obligatoire avant toute vente cash.",
      },
      {
        title: "Choisir un départ",
        body: "Liste des voyages avec places disponibles. Cliquer « Vente guichet ».",
      },
      {
        title: "Émettre le billet",
        body: "Saisir nom, téléphone (fidélité), choisir le siège, colis optionnel. Un ticket = une référence TB- unique + QR.",
      },
      {
        title: "Vente multi-voyageurs",
        body: "Ajouter plusieurs voyageurs : chacun reçoit son propre ticket.",
      },
      {
        title: "Reversement",
        body: "En fin de service : soumettre le montant au comptable. La caisse passe en attente de validation.",
      },
      {
        title: "Scanner",
        body: "À l'embarquement : scanner le QR, marquer le passager à bord, détecter les doublons.",
      },
      {
        title: "Colis",
        body: "Si activé : onglet Colis pour enregistrer des envois autonomes.",
      },
      {
        title: "Ventes compagnie",
        body: "Onglet historique des ventes de la compagnie (lecture + annulation si autorisé).",
      },
    ],
  },
  {
    id: "staff",
    title: "4. Équipe compagnie — Comptable & Contrôleur",
    intro: "Accès : /fr/company/* · Le comptable valide les caisses ; le contrôleur scanne les billets.",
    figure: {
      src: "/manuel/assets/fig-equipe.png",
      caption: "Figure 3 — Espace comptable / contrôleur",
    },
    subsections: [
      {
        title: "Journal des ventes (/company/sales)",
        body: "Toutes les ventes de la compagnie. Filtrer, contrôler, exporter.",
      },
      {
        title: "Rapports voyages (/company/trip-reports)",
        body: "Taux de remplissage, départs, performance par ligne.",
      },
      {
        title: "Validation caisse (/company/cash-register)",
        body: "Approuver les reversements vendeurs. Clôture la session guichet du vendeur.",
      },
      {
        title: "Scanner (/verify/scan)",
        body: "Contrôle embarquement : authenticité billet, statut payé, anti-fraude.",
      },
      {
        title: "Fond de garantie (/company/guarantee-fund)",
        body: "Consultation solde garantie (selon droits).",
      },
    ],
    paragraphs: [
      "Important — Le comptable n'ouvre pas de caisse guichet. Seuls les vendeurs ouvrent leur session journalière.",
    ],
  },
  {
    id: "traveler",
    title: "5. Voyageur — Client final",
    intro: "Accès : site public /fr — recherche sans compte ; réservation avec connexion.",
    figure: {
      src: "/manuel/assets/fig-voyageur.png",
      caption: "Figure 4 — Parcours voyageur",
    },
    subsections: [
      { title: "Rechercher", body: "Ville départ, arrivée, date. Comparer les compagnies et horaires." },
      {
        title: "Réserver",
        body: "Choisir un départ → nom, téléphone, siège, réseau Mobile Money.",
      },
      { title: "Payer", body: "Redirection FedaPay. Le siège n'est confirmé qu'après paiement réussi." },
      {
        title: "Mes réservations",
        body: "Billet avec référence et QR code à présenter à l'embarquement.",
      },
      {
        title: "Fidélité",
        body: "Points compagnie et plateforme, codes promo, parrainage.",
      },
    ],
  },
  {
    id: "daily",
    title: "6. Flux quotidien recommandé",
    bullets: [
      "Matin — Owner vérifie les départs du jour · Vendeur ouvre sa caisse.",
      "Journée — Ventes guichet + réservations en ligne · Contrôleur scanne à l'embarquement.",
      "Soir — Vendeur soumet reversement · Comptable valide · Owner consulte les rapports.",
    ],
    numbered: [
      "Mon entreprise : identité, contacts, logo.",
      "Gares : créer les villes desservies.",
      "Itinéraires : lier gares, fixer tarifs.",
      "Flotte : enregistrer les bus et capacités.",
      "Voyages : programmer les premiers départs.",
      "Équipe : inviter vendeurs et comptables.",
      "Contact, fidélité, codes promo : selon stratégie commerciale.",
    ],
    paragraphs: [
      "Mise en route d'une nouvelle compagnie — ordre recommandé :",
      "Sans gares, itinéraires, bus et voyages, aucune vente n'est possible — ni en ligne ni au guichet.",
    ],
  },
  {
    id: "help",
    title: "7. Aide intégrée",
    paragraphs: [
      "Bouton « Explorer les fonctionnalités » (accueil, header, sidebar Owner ou menu utilisateur) : guide interactif rejouable à tout moment, adapté à votre rôle.",
      "Navigation clavier du guide : flèches ← →, Entrée, Échap.",
    ],
    figure: {
      src: "/manuel/captures/capture-guide.png",
      caption: "Guide interactif — visite des fonctionnalités",
    },
  },
  {
    id: "troubleshooting",
    title: "8. Dépannage rapide",
    subsections: [
      {
        title: "Vente guichet impossible",
        body: "Vérifier que la caisse est ouverte. Message d'erreur affiché en détail dans l'application.",
      },
      {
        title: "Réservation complète",
        body: "Plus de places sur le départ — choisir un autre horaire.",
      },
      {
        title: "Reversement bloqué",
        body: "Un reversement est déjà en attente ; attendre validation comptable.",
      },
      {
        title: "Scanner invalide",
        body: "Billet annulé, non payé ou déjà embarqué — message explicite à l'écran.",
      },
      {
        title: "Fond de garantie insuffisant",
        body: "Recharger le solde depuis le menu Fond de garantie avant d'accepter des réservations en ligne.",
      },
      {
        title: "Programme fidélité inactif",
        body: "La vente guichet reste possible ; seuls les points fidélité sont suspendus tant que le programme n'est pas activé.",
      },
    ],
  },
  {
    id: "recent",
    title: "9. Nouveautés récentes de la plateforme",
    bullets: [
      "Console Owner en blocs — navigation par sections avec indicateurs clés sur l'aperçu.",
      "Multi-compagnie Owner — bascule entre compagnies depuis la sidebar.",
      "Fond de garantie — bloc dédié sur l'aperçu et supervision des retenues réservation.",
      "Accueil connecté en blocs — accès rapide voyage, espace pro et aide.",
      "Gestion utilisateurs super admin — attribution des rôles depuis le panneau admin.",
      "Visite guidée relançable — « Explorer les fonctionnalités » sur l'accueil et la console.",
    ],
    figure: {
      src: "/manuel/captures/capture-accueil.png",
      caption: "Accueil connecté — blocs d'accès rapide",
    },
  },
];

export function canAccessCompanyManual(roles: string[], isSuperAdmin: boolean): boolean {
  return isSuperAdmin || roles.includes("owner");
}
