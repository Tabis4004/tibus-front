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
    title: "5. Scanner un billet — 4 résultats",
    intro:
      "À l'embarquement, scannez le QR code du billet ou saisissez la référence TB-…. L'écran affiche toujours l'un de ces quatre cas.",
    subsections: [
      {
        title: "✅ Billet valide",
        body: "Carte verte — embarquement autorisé. Le passager peut monter. Vous pouvez appuyer sur « Marquer à bord » pour confirmer définitivement sa présence.",
        bullets: ["Vibration courte sur mobile.", "Détails affichés : passager, trajet, siège, prix."],
      },
      {
        title: "⚠️ Scan en doublon",
        body: "Carte orange — le billet a déjà été scanné une première fois à l'embarquement. Vérifiez l'heure du premier scan affichée.",
        bullets: [
          "Double vibration sur mobile.",
          "Refusez un second embarquement avec le même billet.",
        ],
      },
      {
        title: "🚫 Déjà à bord",
        body: "Carte rouge — le passager a déjà été confirmé « à bord ». Embarquement refusé.",
        bullets: ["L'heure de confirmation à bord est indiquée."],
      },
      {
        title: "❌ Embarquement refusé",
        body: "Carte rouge — billet introuvable, annulé, non payé, ou compagnie / gare de départ incorrecte.",
        bullets: [
          "Message fréquent : « Ticket non valide, vérifiez la compagnie d'achat et la gare de départ ».",
          "Vérifiez que le billet appartient bien à votre compagnie si vous êtes vendeur compagnie.",
        ],
      },
    ],
  },
  {
    id: "sales-ledger",
    title: "6. Journal des ventes — filtres et réimpression",
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
