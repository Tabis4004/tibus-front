export const COMMERCIAL_OFFER_BLANK = "………………………";

export type CommercialOfferLocale = "fr" | "en";

export type CommercialOfferField = {
  id: string;
  label: string;
  value?: string;
};

export type CommercialOfferSection = {
  id: string;
  heading: string;
  paragraphs?: string[];
  bullets?: string[];
};

export type CommercialOfferTable = {
  headers: string[];
  rows: string[][];
};

export type CommercialOfferModule = {
  code: string;
  title: string;
  description: string;
  requires?: string;
};

export type CommercialOfferDocument = {
  meta: {
    title: string;
    subtitle: string;
    product: string;
    version: string;
    footer: string;
  };
  letter: {
    title: string;
    fields: CommercialOfferField[];
    subject: string;
    salutation: string;
    paragraphs: string[];
    annexBullets: string[];
    offlineNote: string;
    closing: string;
    signatureFields: CommercialOfferField[];
  };
  technical: {
    title: string;
    subtitle: string;
    fields: CommercialOfferField[];
    sections: CommercialOfferSection[];
    architectureTable: CommercialOfferTable;
    modules: CommercialOfferModule[];
  };
  financial: {
    title: string;
    subtitle: string;
    fields: CommercialOfferField[];
    modulePricingHeaders: string[];
    modulePricingRows: string[][];
    packTable: CommercialOfferTable;
    billingBullets: string[];
    summaryTable: CommercialOfferTable;
    agreementTitle: string;
    agreementFields: CommercialOfferField[];
  };
};

const FR_MODULES: CommercialOfferModule[] = [
  {
    code: "A",
    title: "Billetterie & exploitation",
    description:
      "Ventes au guichet (en ligne et hors ligne), caisse et rapports, flotte, lignes et programmation, réservations, équipe.",
  },
  {
    code: "B",
    title: "Scanner & anti-fraude",
    description: "Contrôle anti-fraude, annulations.",
    requires: "A",
  },
  {
    code: "C",
    title: "Comptabilité analytique",
    description: "Rapports, commissions, gestion des dépenses, compte de résultat.",
    requires: "A",
  },
  {
    code: "D",
    title: "Courrier / colis",
    description: "Envoi de colis sans voyageur, nature de colis.",
  },
  {
    code: "E",
    title: "Performance",
    description: "Options avancées : promo, fidélité, API partenaire.",
    requires: "A",
  },
  {
    code: "F",
    title: "Équipement TPE",
    description: "Terminal de paiement — sur devis.",
  },
];

const EN_MODULES: CommercialOfferModule[] = [
  {
    code: "A",
    title: "Ticketing & operations",
    description:
      "Counter sales (online and offline), cash register and reports, fleet, routes and scheduling, bookings, team.",
  },
  {
    code: "B",
    title: "Scanner & anti-fraud",
    description: "Fraud control, cancellations.",
    requires: "A",
  },
  {
    code: "C",
    title: "Management accounting",
    description: "Reports, commissions, expense management, income statement.",
    requires: "A",
  },
  {
    code: "D",
    title: "Parcel / courier",
    description: "Parcel shipping without a passenger, parcel types.",
  },
  {
    code: "E",
    title: "Performance",
    description: "Advanced options: promos, loyalty, partner API.",
    requires: "A",
  },
  {
    code: "F",
    title: "POS equipment",
    description: "Payment terminal — on quote.",
  },
];

function modulePricingRows(modules: CommercialOfferModule[]): string[][] {
  const rows = modules.map((module) => [
    module.code,
    module.title,
    COMMERCIAL_OFFER_BLANK,
    COMMERCIAL_OFFER_BLANK,
  ]);
  rows.push(["—", "TOTAL modules sélectionnés", COMMERCIAL_OFFER_BLANK, COMMERCIAL_OFFER_BLANK]);
  return rows;
}

export const COMMERCIAL_OFFER_DOCUMENT_FR: CommercialOfferDocument = {
  meta: {
    title: "Modèle d'offre commerciale Tibus",
    subtitle: "Lettre, offre technique et offre financière — démarchage compagnies",
    product: "Plateforme SaaS billetterie bus · Afrique de l'Ouest",
    version: "2026-06",
    footer:
      "Document modèle Tibus — brouillon. Montants et durées à compléter avant envoi. Sans valeur contractuelle tant que non signé.",
  },
  letter: {
    title: "LETTRE COMMERCIALE",
    fields: [
      { id: "attention", label: "À l'attention de" },
      { id: "company", label: "Compagnie de transport" },
      { id: "address", label: "Adresse" },
      { id: "date", label: "Date" },
      { id: "reference", label: "Référence offre" },
    ],
    subject:
      "Proposition de partenariat — Plateforme digitale Tibus pour la gestion des réservations, de la flotte et du pilotage d'activité",
    salutation: "Madame, Monsieur le Directeur,",
    paragraphs: [
      "Nous avons l'honneur de vous adresser la présente proposition dans le cadre du déploiement de Tibus, solution en ligne dédiée aux compagnies de transport routier en Afrique de l'Ouest.",
      "Face aux enjeux de digitalisation des ventes (guichets, paiement mobile, contrôle embarquement) et de visibilité sur l'activité (rapports, caisse, suivi des lignes), Tibus propose une approche modulaire : vous activez uniquement les briques correspondant à votre organisation, sans investissement lourd en infrastructure locale. Nous avons pour ambition de faciliter la gestion quotidienne automatisée et d'accroître votre part de marché grâce à la réservation en libre-service en ligne pour les voyageurs.",
      "Un module dédié permet au partenaire technique qui vend vos billets en ligne en votre nom de disposer d'un fonds de garantie, qui diminue au fur et à mesure des ventes et peut, si vous le jugez utile, devenir négatif.",
      "Notre proposition s'articule autour de trois volets joints à ce document :",
    ],
    annexBullets: [
      "une offre technique détaillant les modules et l'architecture ;",
      "une offre financière modulable selon vos choix fonctionnels ;",
      "les conditions de mise en service et d'accompagnement.",
    ],
    offlineNote:
      "Le système de vente de tickets au guichet (billetterie) Tibus continue de fonctionner jusqu'à 72 h hors connexion, en conservant les données en local jusqu'à la restauration d'Internet.",
    closing:
      "Nous restons à votre entière disposition pour une démonstration personnalisée et l'ajustement des modules à votre réseau de gares, à votre volume de ventes et à vos équipes terrain.\n\nDans l'attente de votre retour, nous vous prions d'agréer, Madame, Monsieur le Directeur, l'expression de nos salutations distinguées.",
    signatureFields: [
      { id: "issuer", label: "Pour Tibus / [Raison sociale émettrice]" },
      { id: "signatory", label: "Nom et qualité du signataire" },
      { id: "contact", label: "Contact (tél. / e-mail)" },
    ],
  },
  technical: {
    title: "OFFRE TECHNIQUE",
    subtitle: "Plateforme Tibus — Architecture et modules fonctionnels",
    fields: [
      { id: "prospect", label: "Prospect" },
      { id: "validity", label: "Date de validité de l'offre" },
    ],
    sections: [
      {
        id: "context",
        heading: "1. Contexte et périmètre",
        paragraphs: [
          "Tibus est une plateforme Software-as-a-Service (SaaS) hébergée dans le cloud. La compagnie dispose d'un espace isolé (données, utilisateurs, paramètres) accessible via navigateur web sur ordinateur, tablette ou smartphone.",
        ],
      },
      {
        id: "onboarding",
        heading: "4. Mise en service & accompagnement",
        bullets: [
          "Création de l'espace compagnie et paramétrage des rôles",
          "Import gares, lignes, bus et horaires (données client)",
          "Formation guichetiers : ___ session(s) de ___ heure(s)",
          "Formation direction : ___ session(s)",
          "Délai indicatif de mise en production : ___ semaines",
          "Support : ___ (canal, horaires, délai incidents bloquants)",
        ],
      },
      {
        id: "prerequisites",
        heading: "5. Prérequis côté compagnie",
        bullets: [
          "Connexion Internet stable sur les guichets",
          "Fichier gares / lignes / horaires / flotte",
          "Convention Mobile Money si paiement en ligne",
          "Référent technique et référent métier désignés",
        ],
      },
      {
        id: "out-of-scope",
        heading: "6. Hors périmètre standard",
        paragraphs: [
          "App native iOS/Android marque blanche, ERP tiers, hébergement on-premise — sur devis séparé.",
        ],
      },
    ],
    architectureTable: {
      headers: ["Couche", "Description"],
      rows: [
        ["Interface utilisateur", "Application web responsive — hébergement cloud"],
        ["Données & sécurité", "PostgreSQL, authentification, isolation par rôle et RLS"],
        ["Services métier", "Fonctions cloud : paiements, notifications, webhooks, contrôle billets"],
        [
          "Paiements",
          "Passerelle Mobile Money — commissions selon réseau opérateur (voyageurs et vendeurs indépendants)",
        ],
      ],
    },
    modules: FR_MODULES,
  },
  financial: {
    title: "OFFRE FINANCIÈRE",
    subtitle: "Grille modulaire — montants en francs CFA (F CFA)",
    fields: [
      { id: "prospect", label: "Prospect" },
      { id: "duration", label: "Durée d'engagement proposée" },
      { id: "validity", label: "Date de validité" },
    ],
    modulePricingHeaders: ["Module", "Désignation", "Mise en service (F CFA)", "Abonnement mensuel (F CFA)"],
    modulePricingRows: modulePricingRows(FR_MODULES),
    packTable: {
      headers: ["Élément", "Montant (F CFA)"],
      rows: [
        ["Mise en service pack complet", COMMERCIAL_OFFER_BLANK],
        ["Abonnement mensuel pack (avant remise)", COMMERCIAL_OFFER_BLANK],
        ["Remise pack complet (___ %)", COMMERCIAL_OFFER_BLANK],
        ["Abonnement mensuel net", COMMERCIAL_OFFER_BLANK],
      ],
    },
    billingBullets: [
      "Mise en service : ___ % à la commande, ___ % à la mise en production",
      "Abonnement : facturation mensuelle d'avance, échéance le ___ du mois",
      "Frais de service réservation : à la charge de ___ (compagnie / voyageur / partagé)",
      "Taux indicatif commissions opérateur : ___ %",
      "Révision tarifaire : après ___ mois, préavis ___ jours",
    ],
    summaryTable: {
      headers: ["Poste", "Valeur"],
      rows: [
        ["Modules retenus", "A ☐  B ☐  C ☐  D ☐  E ☐  F ☐"],
        ["Total mise en service", `${COMMERCIAL_OFFER_BLANK} F CFA`],
        ["Abonnement mensuel", `${COMMERCIAL_OFFER_BLANK} F CFA / mois`],
        ["Durée du contrat", `${COMMERCIAL_OFFER_BLANK} mois`],
        ["Date de démarrage souhaitée", COMMERCIAL_OFFER_BLANK],
      ],
    },
    agreementTitle: "Bon pour accord",
    agreementFields: [
      { id: "client_name", label: "Nom et qualité (client)" },
      { id: "signature", label: "Date et signature" },
      { id: "stamp", label: "Cachet de la compagnie" },
    ],
  },
};

export const COMMERCIAL_OFFER_DOCUMENT_EN: CommercialOfferDocument = {
  meta: {
    title: "Tibus commercial offer template",
    subtitle: "Cover letter, technical offer and financial offer — carrier outreach",
    product: "Bus ticketing SaaS platform · West Africa",
    version: "2026-06",
    footer:
      "Tibus template document — draft. Complete amounts and durations before sending. Not contractually binding until signed.",
  },
  letter: {
    title: "COVER LETTER",
    fields: [
      { id: "attention", label: "Attention" },
      { id: "company", label: "Transport company" },
      { id: "address", label: "Address" },
      { id: "date", label: "Date" },
      { id: "reference", label: "Offer reference" },
    ],
    subject:
      "Partnership proposal — Tibus digital platform for bookings, fleet management and business oversight",
    salutation: "Dear Director,",
    paragraphs: [
      "We are pleased to submit this proposal for deploying Tibus, an online solution dedicated to intercity bus operators in West Africa.",
      "Facing the challenges of sales digitization (counters, mobile payment, boarding control) and operational visibility (reports, cash register, route monitoring), Tibus offers a modular approach: you enable only the building blocks that match your organization, without heavy local infrastructure investment. Our goal is to automate daily operations and grow your market share through self-service online booking for travelers.",
      "A dedicated module gives your online sales partner a guarantee fund that decreases with sales and may, if you choose, go negative.",
      "Our proposal is structured in three parts attached to this document:",
    ],
    annexBullets: [
      "a technical offer detailing modules and architecture;",
      "a financial offer tailored to your functional choices;",
      "onboarding and support conditions.",
    ],
    offlineNote:
      "Tibus counter ticketing works offline for up to 72 hours, keeping data locally until Internet is restored.",
    closing:
      "We remain at your disposal for a personalized demo and to align modules with your station network, sales volume and field teams.\n\nYours sincerely,",
    signatureFields: [
      { id: "issuer", label: "For Tibus / [Issuing company]" },
      { id: "signatory", label: "Name and title of signatory" },
      { id: "contact", label: "Contact (phone / email)" },
    ],
  },
  technical: {
    title: "TECHNICAL OFFER",
    subtitle: "Tibus platform — Architecture and functional modules",
    fields: [
      { id: "prospect", label: "Prospect" },
      { id: "validity", label: "Offer validity date" },
    ],
    sections: [
      {
        id: "context",
        heading: "1. Context and scope",
        paragraphs: [
          "Tibus is a cloud-hosted Software-as-a-Service (SaaS) platform. Each company has an isolated workspace (data, users, settings) accessible via web browser on desktop, tablet or smartphone.",
        ],
      },
      {
        id: "onboarding",
        heading: "4. Onboarding & support",
        bullets: [
          "Company workspace creation and role setup",
          "Import stations, routes, buses and schedules (client data)",
          "Counter staff training: ___ session(s) of ___ hour(s)",
          "Management training: ___ session(s)",
          "Indicative go-live timeline: ___ weeks",
          "Support: ___ (channel, hours, blocking incident SLA)",
        ],
      },
      {
        id: "prerequisites",
        heading: "5. Company prerequisites",
        bullets: [
          "Stable Internet at counters",
          "Stations / routes / schedules / fleet file",
          "Mobile Money agreement if online payment",
          "Designated technical and business contacts",
        ],
      },
      {
        id: "out-of-scope",
        heading: "6. Standard exclusions",
        paragraphs: [
          "White-label native iOS/Android app, third-party ERP, on-premise hosting — separate quote.",
        ],
      },
    ],
    architectureTable: {
      headers: ["Layer", "Description"],
      rows: [
        ["User interface", "Responsive web app — cloud hosting"],
        ["Data & security", "PostgreSQL, authentication, role-based RLS isolation"],
        ["Business services", "Cloud functions: payments, notifications, webhooks, ticket control"],
        [
          "Payments",
          "Mobile Money gateway — operator network fees (travelers and independent sellers)",
        ],
      ],
    },
    modules: EN_MODULES,
  },
  financial: {
    title: "FINANCIAL OFFER",
    subtitle: "Modular grid — amounts in CFA francs (XOF)",
    fields: [
      { id: "prospect", label: "Prospect" },
      { id: "duration", label: "Proposed commitment period" },
      { id: "validity", label: "Validity date" },
    ],
    modulePricingHeaders: ["Module", "Label", "Setup fee (XOF)", "Monthly subscription (XOF)"],
    modulePricingRows: modulePricingRows(EN_MODULES).map((row) =>
      row[1] === "TOTAL modules sélectionnés"
        ? ["—", "TOTAL selected modules", row[2], row[3]]
        : row,
    ),
    packTable: {
      headers: ["Item", "Amount (XOF)"],
      rows: [
        ["Full pack setup fee", COMMERCIAL_OFFER_BLANK],
        ["Monthly pack subscription (before discount)", COMMERCIAL_OFFER_BLANK],
        ["Pack discount (___ %)", COMMERCIAL_OFFER_BLANK],
        ["Net monthly subscription", COMMERCIAL_OFFER_BLANK],
      ],
    },
    billingBullets: [
      "Setup fee: ___ % on order, ___ % at go-live",
      "Subscription: monthly in advance, due on the ___ of each month",
      "Booking service fees: borne by ___ (company / traveler / shared)",
      "Indicative operator commission rate: ___ %",
      "Price review: after ___ months, ___ days notice",
    ],
    summaryTable: {
      headers: ["Item", "Value"],
      rows: [
        ["Selected modules", "A ☐  B ☐  C ☐  D ☐  E ☐  F ☐"],
        ["Total setup fee", `${COMMERCIAL_OFFER_BLANK} XOF`],
        ["Monthly subscription", `${COMMERCIAL_OFFER_BLANK} XOF / month`],
        ["Contract duration", `${COMMERCIAL_OFFER_BLANK} months`],
        ["Desired start date", COMMERCIAL_OFFER_BLANK],
      ],
    },
    agreementTitle: "Approval",
    agreementFields: [
      { id: "client_name", label: "Name and title (client)" },
      { id: "signature", label: "Date and signature" },
      { id: "stamp", label: "Company stamp" },
    ],
  },
};

export const COMMERCIAL_OFFER_DOCUMENTS: Record<CommercialOfferLocale, CommercialOfferDocument> = {
  fr: COMMERCIAL_OFFER_DOCUMENT_FR,
  en: COMMERCIAL_OFFER_DOCUMENT_EN,
};

export function resolveCommercialOfferLocale(locale: string | undefined): CommercialOfferLocale {
  return locale === "en" ? "en" : "fr";
}

export function getCommercialOfferDocument(locale: string | undefined): CommercialOfferDocument {
  return COMMERCIAL_OFFER_DOCUMENTS[resolveCommercialOfferLocale(locale)];
}

export function cloneCommercialOfferDocument(locale: string | undefined): CommercialOfferDocument {
  return structuredClone(getCommercialOfferDocument(locale));
}

export function commercialOfferFieldValue(field: CommercialOfferField): string {
  const trimmed = field.value?.trim();
  return trimmed ? trimmed : COMMERCIAL_OFFER_BLANK;
}
