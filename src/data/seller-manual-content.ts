import type { ManualSection } from "@/data/company-manual-content.ts";

export const SELLER_MANUAL_TITLE = "Manuel vendeur Tibus";
export const SELLER_MANUAL_SUBTITLE =
  "Guide guichet et réservation tiers — ventes, caisse, scan et suivi des billets";

export const SELLER_MANUAL_SECTIONS: ManualSection[] = [
  {
    id: "access",
    title: "1. Accéder à votre espace",
    intro:
      "Ce manuel s'adresse aux vendeurs compagnie (guichet) et aux vendeurs indépendants (réservation tiers). Il ne remplace pas le manuel compagnie réservé aux propriétaires.",
    numbered: [
      "Connectez-vous à Tibus avec votre compte vendeur.",
      "Depuis l'accueil, ouvrez « Vente guichet » ou « Tableau vendeur » (lien /fr/seller).",
      "L'onglet Guichet sert aux ventes du jour ; l'onglet Ventes compagnie (vendeur compagnie uniquement) liste l'historique des billets.",
      "Le bouton Scanner mène au contrôle d'embarquement (/fr/verify/scan).",
      "Ce document est visible uniquement pour les rôles vendeur et vendeur indépendant.",
    ],
    figure: {
      src: "/manuel/captures/seller-real-dashboard.png",
      caption: "Tableau de bord vendeur — onglet Guichet (Tibus Démo Transport)",
    },
  },
  {
    id: "counter-sale",
    title: "2. Vente au guichet (vendeur compagnie)",
    intro:
      "Réservé au rôle vendeur rattaché à une compagnie. Vous encaissez en espèces sur place et émettez un ticket immédiatement.",
    numbered: [
      "Ouvrez d'abord votre caisse du jour (voir section 4) — sans caisse ouverte, la vente est refusée.",
      "Onglet Guichet → choisissez un départ dans « Départs disponibles ».",
      "Indiquez le nombre de passagers : autant de lignes « Nom et prénom » s'affichent.",
      "Renseignez un seul téléphone pour le groupe (fidélité sur le premier contact).",
      "Sélectionnez tous les sièges d'un coup sur le plan (autant que de passagers).",
      "Renseignez le colis une seule fois si besoin, puis validez « Vendre ».",
      "Imprimez ou partagez chaque reçu ; chaque passager reçoit sa propre référence TB-…",
    ],
    bullets: [
      "Un reversement en attente de validation comptable bloque les nouvelles ventes cash.",
      "Le mode affiché en haut du tableau de bord est « Guichet » (et non « Tiers »).",
    ],
    subsections: [
      {
        title: "Formulaire de vente",
        body: "Après avoir choisi un départ, renseignez les passagers, les sièges (sélection multiple) et le colis groupé le cas échéant, puis validez « Vendre ».",
        figure: {
          src: "/manuel/captures/seller-real-sale-form.png",
          caption: "Formulaire guichet — passagers, sièges et colis (exemple Tibus Démo Transport)",
        },
      },
      {
        title: "Reçu billet (POS)",
        body: "Chaque passager reçoit un reçu avec référence TB-…, QR code et détail du trajet. Impression thermique 80 mm / 56 mm ou partage WhatsApp.",
        figure: {
          src: "/manuel/captures/seller-real-receipt.png",
          caption: "Reçu après vente guichet — référence, QR code, colis et total (capture application réelle)",
        },
      },
    ],
  },
  {
    id: "third-party",
    title: "3. Réservation tiers (vendeur indépendant)",
    intro:
      "Réservé au vendeur indépendant : vous réservez pour le compte du voyageur sur toutes les compagnies accessibles, puis le paiement se fait en ligne.",
    numbered: [
      "Onglet Guichet → le mode affiché est « Tiers » / « Réservation tiers ».",
      "Sélectionnez un départ parmi les compagnies du réseau Tibus.",
      "Indiquez le nombre de passagers, leurs noms et un téléphone commun.",
      "Choisissez les sièges sur le plan (sélection multiple).",
      "Colis groupé optionnel, puis choisissez le pays et le réseau Mobile Money.",
      "Validez : le voyageur est redirigé vers le paiement en ligne (Fedapay ou passerelle active).",
      "Le billet n'est définitif qu'après confirmation du paiement.",
    ],
    bullets: [
      "Pas de caisse guichet ni de reversement comptable : vous ne manipulez pas l'encaissement cash compagnie.",
      "Vos commissions vendeur indépendant apparaissent dans le bloc commissions de votre tableau de bord.",
    ],
  },
  {
    id: "cash",
    title: "4. Caisse guichet et reversement",
    intro: "Uniquement pour le vendeur compagnie en vente directe (guichet).",
    subsections: [
      {
        title: "Ouverture de caisse",
        body: "Chaque matin, indiquez le fond de roulement (espèces de départ) et validez « Ouvrir la caisse du jour ».",
        bullets: [
          "Une seule session ouverte par vendeur et par gare.",
          "Les ventes cash s'ajoutent au solde affiché en temps réel.",
        ],
      },
      {
        title: "Prérequis pour le mode offline (point crucial)",
        body: "Le guichet Tibus peut fonctionner hors ligne. Pour que les départs restent disponibles sans connexion internet, le vendeur doit une fois en ligne :",
        numbered: [
          "Ouvrir sa caisse sur la gare.",
          "Laisser charger les départs (mis en cache automatiquement).",
        ],
        bullets: [
          "Ensuite, hors ligne, les départs de cette gare réapparaissent depuis le cache local.",
        ],
      },
      {
        title: "Pendant le service",
        body: "Le solde et le journal des mouvements (ventes, annulations) se rafraîchissent automatiquement.",
      },
      {
        title: "Reversement fin de service",
        body: "En fin de journée, saisissez le montant à reverser (par défaut le solde total) et soumettez au comptable compagnie.",
        bullets: [
          "Le statut passe en « en attente » : les ventes cash sont suspendues jusqu'à validation.",
          "Le comptable valide depuis la console owner → Caisse compagnie.",
          "Après validation, vous pouvez rouvrir une nouvelle session le lendemain.",
        ],
      },
    ],
  },
  {
    id: "scanner",
    title: "5. Scanner un billet — parcours à l'embarquement",
    intro:
      "À l'embarquement, scannez le QR code du billet ou saisissez la référence TB-…. Voici le déroulé type avec les écrans affichés dans l'application.",
    subsections: [
      {
        title: "✅ 1er scan — billet valide",
        body: "Carte verte — embarquement autorisé. Le passager peut monter. Appuyez sur « Marquer à bord » pour confirmer sa présence dans le bus.",
        bullets: [
          "Vibration courte sur mobile.",
          "Détails affichés : passager, trajet, siège, prix, statut payé.",
        ],
        figure: {
          src: "/manuel/captures/seller-scan-valid.png",
          caption: "Premier scan : billet valide, embarquement autorisé",
        },
      },
      {
        title: "✅ Confirmation — passager à bord",
        body: "Après « Marquer à bord », l'écran confirme que le passager est enregistré comme embarqué. Vous pouvez enchaîner avec un autre billet.",
        bullets: ["Bouton « Scanner un autre billet » pour reprendre le contrôle."],
        figure: {
          src: "/manuel/captures/seller-scan-onboard-confirmed.png",
          caption: "Passager confirmé à bord",
        },
      },
      {
        title: "⚠️ 2e scan — alerte doublon",
        body: "Carte orange — le billet a déjà été scanné une première fois à l'embarquement. Vérifiez l'heure du premier scan affichée.",
        bullets: [
          "Double vibration sur mobile.",
          "Refusez un second embarquement avec le même billet.",
        ],
        figure: {
          src: "/manuel/captures/seller-scan-duplicate.png",
          caption: "Second scan : billet déjà scanné à l'embarquement",
        },
      },
      {
        title: "🚫 Scan suivant — déjà à bord",
        body: "Carte rouge — le passager a déjà été confirmé « à bord ». Embarquement refusé.",
        bullets: ["L'heure de confirmation à bord est indiquée."],
        figure: {
          src: "/manuel/captures/seller-scan-already-onboard.png",
          caption: "Passager déjà confirmé — embarquement refusé",
        },
      },
      {
        title: "❌ Embarquement refusé (autres cas)",
        body: "Carte rouge — billet introuvable, annulé, non payé, ou compagnie / gare de départ incorrecte.",
        bullets: [
          "Message fréquent : « Ticket non valide, vérifiez la compagnie d'achat et la gare de départ ».",
          "Vérifiez que le billet appartient bien à votre compagnie si vous êtes vendeur compagnie.",
        ],
      },
    ],
  },
  {
    id: "pay-at-station",
    title: "6. Reçu « Payer en gare » — encaissement à l'arrivée",
    intro:
      "Certaines compagnies activent l'option « Payer en gare » : le voyageur ne paie en ligne que les frais (plateforme + gateway), pas le prix du billet. Il se présente à la gare de départ avec un reçu de réservation, pas un billet acquitté. Il n'y a pas d'écran dédié pour ça dans l'application — reconnaissance visuelle et encaissement manuel avant l'embarquement.",
    subsections: [
      {
        title: "Reconnaître un reçu de réservation",
        body: "Il ressemble à un reçu normal mais porte un encart orange bien visible, différent du billet standard.",
        bullets: [
          "Titre « ⚠ REÇU DE RÉSERVATION » dans un encadré orange/jaune.",
          "Mention « Ceci est un reçu de réservation à payer dans la gare du départ ».",
          "Ligne « Montant dû à la compagnie : [devise] [montant] » — c'est le montant M à encaisser.",
          "Le texte exact peut varier : il est personnalisable par la plateforme, mais l'encart orange et le montant dû restent toujours présents.",
        ],
        figure: {
          src: "/manuel/captures/seller-real-receipt.png",
          caption: "Repère visuel : encart orange « reçu de réservation » avec montant dû",
        },
      },
      {
        title: "Procédure à l'arrivée du voyageur",
        body: "Avant de scanner et embarquer le passager :",
        numbered: [
          "Vérifiez la référence TB-… du reçu et l'identité du passager.",
          "Encaissez en espèces exactement le montant affiché sur « Montant dû à la compagnie ».",
          "Notez l'encaissement selon la procédure de votre compagnie (aucune validation automatique dans l'app pour cette étape).",
          "Poursuivez ensuite avec le scan normal du billet (voir section 5 — Scanner un billet).",
        ],
        bullets: [
          "En cas de doute sur le montant ou de reçu qui ne semble pas correspondre à un vrai départ, contactez votre owner ou responsable avant d'embarquer le passager.",
          "Cette étape d'encaissement est manuelle : le scan à l'embarquement ne vérifie pas que le montant a été payé, faites-le systématiquement avant de « Marquer à bord ».",
        ],
      },
    ],
  },
  {
    id: "sales-ledger",
    title: "7. Journal des ventes — filtres et réimpression",
    intro:
      "Onglet « Ventes compagnie » du tableau vendeur (vendeur compagnie). Liste tous les billets vendus ou réservés pour votre compagnie.",
    subsections: [
      {
        title: "Recherche et filtres",
        body: "Affinez la liste avant d'agir sur un billet.",
        bullets: [
          "Recherche texte : nom du voyageur ou numéro de ticket (TB-…).",
          "Canal : Tous · Voyageur (en ligne) · Guichet · Réservation tiers.",
          "Période de vente : aujourd'hui, 7 jours, 30 jours, ce mois, ou toutes périodes.",
          "Date de départ : filtre sur le jour du voyage.",
          "Bouton « Réinitialiser » pour effacer tous les filtres.",
        ],
      },
      {
        title: "Lire le tableau",
        body: "Chaque ligne affiche la référence, le voyageur, le trajet, la date de départ, le canal, le vendeur, le montant et le statut.",
        bullets: [
          "Guichet = vente cash au comptoir.",
          "Réservation tiers = billet pris par un agent indépendant.",
          "Voyageur = achat en ligne direct.",
        ],
      },
      {
        title: "Réimprimer un ticket guichet",
        body: "Le bouton « Réimprimer » n'apparaît que pour les ventes au guichet non annulées.",
        bullets: [
          "Filtrez si besoin (référence ou nom du passager).",
          "Cliquez « Réimprimer » sur la ligne concernée.",
          "Le reçu POS s'affiche : imprimez ou partagez via WhatsApp.",
        ],
      },
      {
        title: "Annulation",
        body: "Si votre rôle le permet (vendeur, chauffeur ou owner), le bouton Annuler ouvre un calcul de pénalité avant confirmation. En cas de doute, contactez votre responsable.",
      },
    ],
  },
];
