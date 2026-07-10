export type ManualFigure = {
  src: string;
  caption: string;
};

export type ManualSubsection = {
  title: string;
  body: string;
  bullets?: string[];
  numbered?: string[];
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
    body: "Tableau de bord en blocs : indicateurs clés (revenus, caisse, commissions, voyages) puis accès rapide par section — Commercial, Finance & garantie, Exploitation, Paramètres. Le bloc Fond de garantie affiche le solde en direct depuis l'aperçu.",
    bullets: [
      "Indicateurs du jour : revenus, caisse guichet, commissions, nombre de voyages programmés.",
      "Section Finance & garantie : fond de garantie, caisse gare, commissions gestionnaires, dépenses, compte de résultat.",
      "Chaque bloc est cliquable et mène à la page dédiée.",
    ],
    figure: {
      src: "/manuel/captures/owner-real-overview.png",
      caption: "Aperçu Owner — blocs Finance & garantie visibles (compte tibustest@gmail.com)",
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
    body: "Module d'envoi de colis gare à gare sans billet voyageur (module D, activé par la plateforme). Le vendeur enregistre l'envoi et encaisse le fret au guichet ; l'owner configure ici les natures de colis et les notifications SMS. Accès : sidebar Owner → Colis autonomes (/owner/colis).",
    bullets: [
      "Prérequis : module D « Colis » activé sur votre compagnie par la plateforme (fiche admin). Sinon la page affiche « module désactivé ».",
      "Natures de colis : créez vos catégories (ex. Carton, Enveloppe, Sac…), activez/désactivez ou supprimez-les. Le vendeur choisit une nature à chaque envoi.",
      "Notifications SMS à l'expéditeur/destinataire, activables statut par statut : Enregistrement au guichet · Chargement en soute · Arrivée à destination · Remise au destinataire.",
      "L'option SMS est soumise à autorisation plateforme (module D + option SMS) : si elle n'est pas accordée, les interrupteurs restent verrouillés.",
      "Le montant du fret est saisi librement par le vendeur au guichet et passe par sa caisse journalière.",
      "Comptabilité : les ventes colis alimentent le produit 7012 du compte de résultat SYSCOHADA, distinct des billets (7011).",
    ],
    figure: { src: "/manuel/captures/owner-real-colis.png", caption: "Colis autonomes — natures et notifications SMS" },
  },
  {
    title: "Fond de garantie",
    body: "Réserve financière obligatoire pour accepter les réservations voyageur en ligne. Chaque billet payé en ligne débite le fond ; une annulation crédite le solde (libération).",
    bullets: [
      "Bloc dédié sur l'aperçu : solde actuel, badge si dépôt(s) en attente de validation.",
      "Page /owner/guarantee-fund : solde, journal des mouvements (Dépôt · Réservation · Libération), historique des dépôts plateforme.",
      "Retenue réservation : à l'émission d'un billet voyageur, le montant nominal M est débité du fond.",
      "Option « Autoriser solde négatif » : permet de continuer les ventes en ligne si un dépôt plateforme est en retard (réseau).",
      "Si le solde est insuffisant et l'option désactivée, les nouvelles réservations en ligne sont bloquées.",
    ],
    figure: {
      src: "/manuel/captures/owner-real-guarantee-fund.png",
      caption: "Fond de garantie — solde, mouvements et paramétrage (capture réelle)",
    },
  },
  {
    title: "Commissions gestionnaires",
    body: "Suivi des parts des chefs de gare configurées sur chaque gare (menu Gares). Deux flux distincts : guichet et réservations en ligne.",
    bullets: [
      "Guichet : la part gestionnaire est déjà perçue en espèces par le vendeur — affichée à titre informatif.",
      "Réservations en ligne : part à reverser par la compagnie au gestionnaire de gare.",
      "Configurer le gestionnaire et les % (guichet / réservation) dans Gares → modifier une gare.",
      "Bouton « Marquer payé » pour solder les commissions réservation en attente.",
    ],
    figure: {
      src: "/manuel/captures/owner-real-gare-manager-commissions.png",
      caption: "Commissions gestionnaires de gare (capture réelle)",
    },
  },
  {
    title: "Dépenses",
    body: "Journal des charges de la compagnie avec imputation obligatoire — membre d'équipe ou bus rattaché à une gare. Alimente le compte de résultat SYSCOHADA.",
    bullets: [
      "Types de dépenses : libellé + compte OHADA (ex. carburant, entretien, salaires).",
      "Nouvelle dépense : montant, date, type, imputation équipe ou bus+gare.",
      "Filtre par période et total automatique.",
      "Lien direct vers le compte de résultat depuis cette page.",
    ],
    figure: {
      src: "/manuel/captures/owner-real-expenses.png",
      caption: "Dépenses — types et journal (capture réelle)",
    },
  },
  {
    title: "Compte de résultat",
    body: "Bilan périodique selon le référentiel SYSCOHADA : produits d'exploitation (billets, colis), charges (dépenses saisies) et résultat net.",
    bullets: [
      "Période libre (du / au) avec actualisation.",
      "Produits 7011 (tickets) et 7012 (colis) calculés depuis les ventes payées.",
      "Charges issues du journal des dépenses, ventilées par compte OHADA.",
      "Résultat net = produits − charges.",
    ],
    figure: {
      src: "/manuel/captures/owner-real-income-statement.png",
      caption: "Compte de résultat SYSCOHADA (capture réelle)",
    },
  },
  {
    title: "API partenaire",
    body: "Connecter un ERP ou un autre système de billetterie : synchroniser les départs Tibus et lire la disponibilité en temps réel. Les ventes partenaire utilisent le canal partner_api.",
    bullets: [
      "Générer une clé API (affichée une seule fois) : tibus_…",
      "Endpoints : mappings gares, sync départs (PUT), disponibilité (GET), ventes et holds (POST bookings).",
      "Webhooks HMAC signés : booking.created, booking.confirmed, booking.cancelled, departure.synced.",
      "Base URL : …/functions/v1/partner-itinerary-api — doc technique docs/PARTNER_ITINERARY_API.md.",
      "Canal partner_api : hors fond de garantie voyageur (contrairement aux ventes tibus.app).",
    ],
    figure: {
      src: "/manuel/captures/owner-real-partner-api.png",
      caption: "API partenaire itinéraires — clés et webhooks (capture réelle)",
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
    body: "Contrôle QR à l'embarquement (/fr/verify/scan). Quatre états du cadran : vert (1er contrôle), orange (déjà vérifié), vert confirmé (à bord), rouge (fraude / déjà embarqué). Un billet d'une autre compagnie est toujours refusé.",
    bullets: [
      "Accès : owner, contrôleur, vendeur, chauffeur (menu Owner, espace guichet ou accueil connecté).",
      "Étape 1 — Vert : premier scan, billet payé → « Marquer à bord ».",
      "Étape 2 — Orange : QR déjà scanné une fois (horodatage du 1er contrôle).",
      "Étape 3 — Vert confirmé : passager accepté dans le bus après « Marquer à bord ».",
      "Étape 4 — Rouge : re-scan après embarquement confirmé — alerte anti-fraude.",
      "Règle inter-compagnies : gare_id puis compagnie_id — message « Ticket non valide, vérifiez la compagnie d'achat et la gare de départ ».",
    ],
    figure: {
      src: "/manuel/captures/scan-controle-vert-valid.png",
      caption: "Étape 1 — Vert : premier contrôle de validité (capture HD Tibus Démo)",
    },
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
        body: "À l'embarquement : 1) vert premier scan → « Marquer à bord » ; 2) orange si déjà vérifié ; 3) vert confirmé une fois à bord ; 4) rouge si re-scan après embarquement.",
        figure: {
          src: "/manuel/captures/scan-controle-vert-valid.png",
          caption: "Étape 1 — Vert : billet valide, embarquement autorisé",
        },
      },
      {
        title: "Colis",
        body: "Si le module D est activé : onglet Colis pour enregistrer des envois autonomes gare à gare (expéditeur, destinataire, nature, poids, montant fret), encaisser au guichet et faire avancer le statut Enregistré → Chargé → Arrivé → Livré. Voir la section dédiée du manuel vendeur.",
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
        body: "Contrôle embarquement en quatre étapes. Seuls les billets de la compagnie du contrôleur sont acceptés (contrôle gare_id, repli compagnie_id).",
        bullets: [
          "Vert (1) : premier scan — détails passager, trajet, siège, badge Payé, bouton « Marquer à bord ».",
          "Orange (2) : billet déjà scanné une fois — horodatage du premier contrôle.",
          "Vert (3) : passager confirmé à bord après validation du contrôleur.",
          "Rouge (4) : re-scan après embarquement — alerte fraude, bouton « Scanner un autre billet ».",
          "Autre compagnie : « Ticket non valide, vérifiez la compagnie d'achat et la gare de départ ».",
        ],
        figure: {
          src: "/manuel/captures/scan-controle-orange-doublon.png",
          caption: "Étape 2 — Orange : déjà vérifié une fois",
        },
      },
      {
        title: "Fond de garantie (/company/guarantee-fund)",
        body: "Consultation solde garantie et mouvements (selon droits owner / comptable).",
      },
      {
        title: "Commissions gestionnaires",
        body: "Lecture des parts gares ; le reversement réservation est initié par l'owner.",
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
        title: "Scanner — cadran rouge ou autre compagnie",
        body: "Rouge (étape 4) : passager déjà embarqué confirmé — ne pas laisser monter à nouveau. Autre compagnie : le serveur compare gare_id (défaut) puis compagnie_id ; message unique « Ticket non valide, vérifiez la compagnie d'achat et la gare de départ ». Autres refus rouge : billet annulé, non payé ou référence introuvable.",
      },
      {
        title: "Fond de garantie insuffisant",
        body: "Recharger le solde depuis Fond de garantie, ou activer « Autoriser solde négatif » si un dépôt plateforme est en attente. Vérifier le journal des mouvements (retenues réservation).",
      },
      {
        title: "Commissions gestionnaire vides",
        body: "Assigner un gestionnaire et des % sur la gare (menu Gares). Les données apparaissent après les premières ventes guichet ou réservations.",
      },
      {
        title: "Compte de résultat à zéro",
        body: "Vérifier la période sélectionnée et qu'il existe des ventes payées ou des dépenses saisies sur l'intervalle.",
      },
      {
        title: "API partenaire — places incorrectes",
        body: "Les holds partenaire (mode hold) réduisent aussi la disponibilité. Annuler les holds expirés ou confirmer les réservations en attente.",
      },
      {
        title: "Programme fidélité inactif",
        body: "La vente guichet reste possible ; seuls les points fidélité sont suspendus tant que le programme n'est pas activé.",
      },
    ],
  },
  {
    id: "finance",
    title: "9. Finance, garantie & API partenaire",
    intro:
      "Ces modules sont regroupés dans la section « Finance & garantie » de l'aperçu Owner. Ils couvrent la sécurisation des réservations en ligne, la rémunération des chefs de gare, la comptabilité de gestion et l'intégration technique avec des systèmes externes.",
    subsections: [
      {
        title: "Fond de garantie — principe",
        body: "Le fond de garantie protège la plateforme et le voyageur : tant qu'un billet en ligne n'est pas honoré ou annulé, le montant nominal reste « retenu » sur le solde compagnie.",
        bullets: [
          "Dépôt (crédit) : recharge validée par la comptabilité plateforme après relevé bancaire.",
          "Réservation (débit) : chaque billet voyageur payé sur tibus.app débite M XOF du fond.",
          "Libération (crédit) : annulation ou remboursement recrédite le fond.",
          "Supervision : tableau « Mouvements du fond » avec date, type, montant, solde courant et référence billet.",
        ],
        figure: {
          src: "/manuel/captures/owner-real-guarantee-fund.png",
          caption: "Journal des retenues et libérations",
        },
      },
      {
        title: "Commissions gestionnaires de gare",
        body: "Chaque gare peut avoir un gestionnaire (rôle gestionnaire_gare) avec un % guichet et un % réservation distincts.",
        bullets: [
          "Configuration : Owner → Gares → modifier → gestionnaire + parts %.",
          "Tableau temps réel : CA guichet, part déjà encaissée, part réservation due, montants payés / en attente.",
          "Seules les commissions réservation nécessitent un reversement par la compagnie.",
        ],
        figure: {
          src: "/manuel/captures/owner-real-gare-manager-commissions.png",
          caption: "Suivi des parts par gare",
        },
      },
      {
        title: "Dépenses & compte de résultat",
        body: "La saisie des dépenses alimente automatiquement le compte de résultat. Les produits proviennent des ventes billets et colis enregistrées dans Tibus.",
        bullets: [
          "11 types de dépenses preset à la création de la compagnie (comptes OHADA).",
          "Imputation obligatoire : évite les charges « non affectées ».",
          "Compte de résultat : filtre période, section I Produits, section II Charges, résultat net.",
        ],
        figure: {
          src: "/manuel/captures/owner-real-income-statement.png",
          caption: "Compte de résultat — produits et charges",
        },
      },
      {
        title: "API partenaire — mise en œuvre",
        body: "Permet à un logiciel tiers de pousser ses départs vers Tibus et de vendre sans passer par le site voyageur. L'inventaire des places reste unique côté Tibus.",
        bullets: [
          "1. Générer une clé API dans Owner → Opérations → API partenaire.",
          "2. Mapper les gares externes : POST /v1/gares/mappings.",
          "3. Synchroniser les départs : PUT /v1/departures (idempotent sur externalDepartureId).",
          "4. Consulter les places : GET /v1/departures/{id}/availability.",
          "5. Vendre ou bloquer : POST /v1/bookings (mode sale ou hold), puis confirm / cancel.",
          "6. Recevoir les événements : configurer un webhook (secret whsec_…, signature HMAC).",
        ],
        figure: {
          src: "/manuel/captures/owner-real-partner-api.png",
          caption: "Console API partenaire — point d'entrée et routes",
        },
      },
      {
        title: "API partenaire — exemple d'appel",
        body: "Authentification sur chaque requête (sauf /v1/health) :",
        bullets: [
          "En-tête : X-Api-Key: tibus_… ou Authorization: Bearer tibus_…",
          "Sync départ : PUT …/v1/departures avec externalDepartureId, departureAt, capacity, price, origin/destination.",
          "Vente : POST …/v1/bookings avec mode sale, passengerName, seatNumber, externalPaymentRef → ticket TB-…",
          "Hold 15 min : POST …/v1/bookings avec mode hold → POST …/confirm pour émettre le billet.",
        ],
      },
      {
        title: "Payer en gare — activation",
        body: "Option qui change ce que le voyageur règle en ligne : au lieu du prix billet complet, il ne paie que les frais plateforme et gateway (X+Y+Z+F). Le prix du billet (M) reste dû en espèces à la gare de départ, et un « reçu de réservation » est émis à la place d'un billet acquitté.",
        bullets: [
          "Accès : page /fr/admin/company/{votre companyId} — pas encore reliée par un lien dans le menu Owner, s'y rendre directement par l'URL (l'ID de la compagnie est visible dans Mon entreprise).",
          "Vous ne pouvez activer/désactiver cette option que pour votre propre compagnie — pas pour les autres compagnies de la plateforme.",
          "Le texte affiché sur le reçu (titre, mention, préfixe du montant dû) est fixé par le super administrateur Tibus et s'applique à toutes les compagnies ; vous ne pouvez pas le modifier.",
          "Une fois activée, informez votre équipe guichet : les voyageurs qui arrivent avec un reçu de réservation doivent régler M en espèces avant l'embarquement (voir le manuel vendeur, section « Payer en gare »).",
        ],
      },
    ],
  },
  {
    id: "boarding-control",
    title: "10. Contrôle embarquement — les quatre étapes du cadran",
    intro:
      "Le scanner (/fr/verify/scan) enregistre chaque contrôle avec horodatage. Les captures ci-dessous proviennent de l'application réelle (billet TB-E46A7348 · Tibus Démo Transport). Le téléphone vibre différemment selon la couleur (succès / alerte / refus).",
    subsections: [
      {
        title: "Étape 1 — Vert : premier contrôle de validité",
        body: "Premier scan d'un billet payé et émis par votre compagnie. Message « Billet valide — embarquement autorisé ». La fiche affiche passager, trajet, gare de départ, horaire, bus, siège et prix. Action obligatoire : appuyer sur « Marquer à bord » pour confirmer l'embarquement physique.",
        bullets: [
          "Le scan enregistre l'horodatage du premier contrôle (boarding).",
          "Saisie manuelle TB-… possible si le QR est illisible.",
          "Vibration courte de succès sur mobile.",
        ],
        figure: {
          src: "/manuel/captures/scan-controle-vert-valid.png",
          caption: "Étape 1 — Vert : premier contrôle · TB-E46A7348 · Oumarou Abdala",
        },
      },
      {
        title: "Étape 2 — Orange : déjà vérifié une fois",
        body: "Le même QR est scanné une seconde fois avant confirmation « Marquer à bord ». Alerte « Billet déjà scanné à l'embarquement » avec la date/heure du premier scan. Le contrôleur peut encore valider l'embarquement si le passager est bien présent.",
        bullets: [
          "Cas typique : deux agents scannent le même billet, ou re-scan accidentel.",
          "Vibration en double impulsion (alerte).",
          "Le bouton « Marquer à bord » reste disponible.",
        ],
        figure: {
          src: "/manuel/captures/scan-controle-orange-doublon.png",
          caption: "Étape 2 — Orange : déjà vérifié une fois",
        },
      },
      {
        title: "Étape 3 — Vert confirmé : client accepté à bord (on board)",
        body: "Après « Marquer à bord », l'écran confirme que le passager est accepté dans le bus. Le statut ticket passe à embarqué. Le contrôleur peut enchaîner sur « Scanner un autre billet ».",
        bullets: [
          "Horodatage de confirmation enregistré côté serveur (onBoardAt).",
          "Vibration de succès identique à l'étape 1.",
          "Ce passager ne doit plus être embarqué une seconde fois.",
        ],
        figure: {
          src: "/manuel/captures/scan-controle-vert-onboard.png",
          caption: "Étape 3 — Vert confirmé : passager accepté à bord",
        },
      },
      {
        title: "Étape 4 — Rouge : alerte fraude (déjà embarqué)",
        body: "Si le QR est scanné à nouveau après l'étape 3, le cadran passe au rouge : passager déjà à bord. Embarquement refusé. Bouton « Scanner un autre billet » uniquement — aucune remise à bord possible sans intervention guichet.",
        bullets: [
          "Date/heure de confirmation à bord affichée.",
          "Vibration longue en triple impulsion (refus).",
          "Protection anti-fraude : un billet = un embarquement.",
        ],
        figure: {
          src: "/manuel/captures/scan-controle-rouge-fraude.png",
          caption: "Étape 4 — Rouge : alerte fraude, déjà embarqué",
        },
      },
      {
        title: "Règle inter-compagnies (obligatoire)",
        body: "Une compagnie ne peut pas scanner le billet d'une autre. Le serveur vérifie d'abord la gare de départ du billet (gare_id), puis en repli la compagnie émettrice (compagnie_id). En cas d'échec, le résultat est rouge avec le message exact :",
        bullets: [
          "« Ticket non valide, vérifiez la compagnie d'achat et la gare de départ »",
          "Aucune fiche passager complète n'autorise l'embarquement cross-compagnie.",
          "Le contrôleur doit orienter le voyageur vers la compagnie émettrice du billet.",
        ],
      },
      {
        title: "Procédure recommandée à l'embarquement",
        body: "Flux standard pour former les contrôleurs :",
        bullets: [
          "1. Ouvrir Scanner (Owner, guichet ou accueil connecté).",
          "2. Scanner le QR → si vert (étape 1), vérifier identité et siège.",
          "3. Appuyer « Marquer à bord » → vert confirmé (étape 3).",
          "4. Si orange (étape 2) : vérifier que c'est le même passager, puis confirmer ou refuser.",
          "5. Si rouge (étape 4) ou autre compagnie : ne pas embarquer.",
        ],
        figure: {
          src: "/manuel/captures/owner-real-scan.png",
          caption: "Page scanner — caméra et saisie manuelle TB-…",
        },
      },
    ],
  },
  {
    id: "recent",
    title: "11. Nouveautés récentes de la plateforme",
    bullets: [
      "Console Owner en blocs — navigation par sections avec indicateurs clés sur l'aperçu.",
      "Multi-compagnie Owner — bascule entre compagnies depuis la sidebar.",
      "Fond de garantie — bloc dédié sur l'aperçu, journal des retenues réservation et option solde négatif.",
      "Commissions gestionnaires — suivi guichet vs réservations par gare.",
      "Dépenses & compte de résultat SYSCOHADA — charges imputées et bilan périodique.",
      "API partenaire — sync itinéraires, disponibilité temps réel, ventes et webhooks.",
      "Accueil connecté en blocs — accès rapide voyage, espace pro et aide.",
      "Visite guidée relançable — « Explorer les fonctionnalités » sur l'accueil et la console.",
      "Cadran de contrôle embarquement — quatre étapes (vert → orange → vert confirmé → rouge) avec captures HD réelles.",
    ],
    figure: {
      src: "/manuel/captures/owner-real-overview.png",
      caption: "Aperçu Owner — section Finance & garantie (capture tibustest@gmail.com)",
    },
  },
];

export function canAccessCompanyManual(roles: string[], isSuperAdmin: boolean): boolean {
  // admin_pays inclus : la nav (getManualNavItems) lui montre ce manuel comme
  // référence pour former/accompagner les owners de son pays.
  return isSuperAdmin || roles.includes("owner") || roles.includes("admin_pays");
}
