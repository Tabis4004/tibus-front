import type { ManualSection } from "@/data/company-manual-content.ts";

export const COUNTRY_ADMIN_MANUAL_TITLE = "Manuel administrateur pays Tibus";
export const COUNTRY_ADMIN_MANUAL_SUBTITLE =
  "Guide admin pays — pilotage des commissions et du fond de garantie sur votre territoire";

export const COUNTRY_ADMIN_MANUAL_SECTIONS: ManualSection[] = [
  {
    id: "role",
    title: "1. Votre rôle d'administrateur pays",
    intro:
      "L'admin pays est un rôle plateforme rattaché à un pays précis. Vous représentez Tibus auprès des transporteurs et des équipes commerciales de votre territoire.",
    bullets: [
      "Périmètre national : vos actions portent sur les compagnies et les flux du pays qui vous est assigné.",
      "Différence avec le super admin : celui-ci gère toute la plateforme (utilisateurs, géographie, abonnements, CMS…). Vous concentrez vos actions sur la régulation financière locale.",
      "Droits principaux : manage_country, suivi des commissions, supervision du fond de garantie, lecture des rapports liés à votre pays.",
    ],
    paragraphs: [
      "Votre compte doit porter le rôle admin_pays avec un countryId en base. Sans ce rattachement, le panneau admin reste inaccessible.",
    ],
  },
  {
    id: "access",
    title: "2. Accéder à votre espace",
    numbered: [
      "Connectez-vous à Tibus avec votre compte admin pays.",
      "Depuis l'accueil, ouvrez le bloc « Panneau admin » ou allez sur /fr/admin.",
      "Seuls deux onglets vous sont proposés : Commissions et Fond garantie.",
      "Consultez le journal d'audit (HUB) en bas de chaque onglet pour retracer vos modifications.",
    ],
    subsections: [
      {
        title: "Page dédiée fond de garantie",
        body: "Depuis l'onglet Fond garantie, le bouton « Ouvrir la page dédiée » mène à /fr/admin/guarantee-fund pour un écran pleine largeur.",
      },
      {
        title: "Ce manuel",
        body: "Disponible sur /fr/manual/admin-pays pour vous et les super administrateurs. Il n'est pas visible des propriétaires de compagnie ni des voyageurs.",
      },
    ],
  },
  {
    id: "commissions",
    title: "3. Module Commissions",
    intro:
      "Vous fixez la part Tibus sur les ventes de billets et les exceptions par compagnie. Les réglages s'appliquent aux nouvelles transactions selon les règles SQL de la plateforme.",
    subsections: [
      {
        title: "Synthèse en haut de page",
        body: "Trois indicateurs : commissions en attente, commissions déjà réglées, volume de billets concernés. Permet un contrôle rapide avant d'ajuster les taux.",
      },
      {
        title: "Taux par pays",
        body: "Définissez le pourcentage par défaut pour votre pays et qui le paie : la compagnie ou le voyageur (frais en sus du billet).",
        bullets: [
          "Taux entre 0 et 100 %.",
          "Enregistrez chaque ligne modifiée avec le bouton dédié.",
          "Supprimez un taux configuré si vous devez revenir au comportement par défaut.",
        ],
      },
      {
        title: "Exceptions par compagnie",
        body: "Certaines compagnies peuvent négocier un taux différent du barème national.",
        bullets: [
          "Sélectionnez la compagnie, saisissez le taux et le payeur.",
          "Utilisez « Ajouter » pour créer l'exception.",
          "Modifiez ou supprimez une exception existante depuis la liste.",
        ],
      },
      {
        title: "Bonnes pratiques",
        body: "Documentez en interne tout changement de taux avant modification. Vérifiez l'impact sur les propriétaires concernés et utilisez le journal HUB comme trace officielle.",
      },
    ],
  },
  {
    id: "guarantee",
    title: "4. Fond de garantie des compagnies",
    intro:
      "Le fond de garantie sécurise les réservations en ligne : une retenue peut être appliquée sur le solde de la compagnie lors d'une vente web.",
    subsections: [
      {
        title: "Consulter une compagnie",
        body: "Choisissez la compagnie dans la liste. Vous voyez le solde actuel, l'historique des mouvements (recharges, retenues, ajustements) et les demandes de dépôt en attente.",
      },
      {
        title: "Dépôts et justificatifs",
        body: "Les propriétaires peuvent soumettre une recharge avec pièce jointe. Vous contrôlez la cohérence du montant et du reçu avant validation côté processus métier.",
      },
      {
        title: "Alertes opérationnelles",
        body: "Un solde insuffisant bloque ou limite les réservations en ligne pour la compagnie. Anticipez en informant le transporteur avant la mise en vente de nouveaux départs.",
      },
    ],
    bullets: [
      "Le fond de garantie est distinct de la caisse guichet vendeur.",
      "Les retenues liées aux billets web apparaissent dans le journal de la compagnie.",
      "La page /fr/admin/guarantee-fund reprend le même gestionnaire en vue élargie.",
    ],
  },
  {
    id: "workflow",
    title: "5. Routine recommandée",
    numbered: [
      "Hebdomadaire — parcourir les commissions en attente et les soldes garantie bas.",
      "Lors d'une nouvelle compagnie — vérifier le taux pays applicable ou créer une exception si accord commercial.",
      "Après incident de paiement — croiser journal HUB, mouvements garantie et message propriétaire.",
      "Avant fin de mois — exporter mentalement les KPI commissions (en attente / payées) pour reporting interne Tibus.",
    ],
  },
  {
    id: "troubleshooting",
    title: "6. Dépannage rapide",
    subsections: [
      {
        title: "Onglets admin manquants",
        body: "Vérifiez que votre compte possède bien admin_pays avec le countryId correct. Le super admin peut corriger l'attribution depuis Utilisateurs.",
      },
      {
        title: "Commissions Supabase indisponibles",
        body: "Message « scripts SQL » : demandez l'application des migrations commissions côté base Supabase.",
      },
      {
        title: "Impossible d'enregistrer un taux",
        body: "Le taux doit être un nombre entre 0 et 100. Rechargez la page si un brouillon semble bloqué.",
      },
      {
        title: "Compagnie absente de la liste garantie",
        body: "Seules les compagnies actives du pays chargé apparaissent. Vérifiez le pays de la compagnie en base.",
      },
      {
        title: "Interrupteur « Payer en gare » grisé",
        body: "Sur la fiche compagnie (/fr/admin/company/:companyId), l'option « Payer en gare » vous est affichée en lecture seule : vous voyez si elle est active et son message de reçu, mais vous ne pouvez ni l'activer ni la désactiver.",
        bullets: [
          "Seuls le propriétaire de la compagnie (pour sa propre compagnie) et le super administrateur peuvent basculer l'interrupteur.",
          "Le message affiché sur le reçu de réservation est modifiable par le super administrateur uniquement (il s'applique à toutes les compagnies).",
          "Pour toute demande d'activation, orientez la compagnie vers son propriétaire ou remontez la demande au super administrateur.",
        ],
      },
    ],
  },
  {
    id: "superadmin",
    title: "7. Note pour le super administrateur",
    intro:
      "Si vous lisez ce manuel avec un compte super admin, vous disposez de tous les onglets admin en plus de ce périmètre pays.",
    bullets: [
      "Utilisez ce guide pour former un admin pays ou pour intervenir sur son territoire.",
      "Le manuel compagnie (/fr/manual/compagnie) couvre les propriétaires et leur console Owner.",
      "Ne partagez pas ce document aux propriétaires : il décrit des réglages plateforme sensibles.",
    ],
  },
];

export function canAccessCountryAdminManual(roles: string[], isSuperAdmin: boolean): boolean {
  return isSuperAdmin || roles.includes("admin_pays");
}
