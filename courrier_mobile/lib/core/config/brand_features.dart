/// Bascules de fonctionnalités PAR MARQUE — compilées en dur (pas
/// modifiables à l'exécution), au même titre que le logo/nom/couleurs (voir
/// tool/apply_brand.py). Alimentées via --dart-define par
/// tool/build_client.sh, qui les lit depuis branding/<client>/brand.json
/// (champ "features") — voir tool/brand_dart_defines.py pour le pont entre
/// les deux.
///
/// Absence du champ dans brand.json => pas de --dart-define émis => la
/// valeur par défaut ci-dessous s'applique : comportement inchangé pour
/// tout client qui ne définit rien.
///
/// Cas d'usage : SIS Courrier est un logiciel métier interne (pas d'accès
/// client aux réservations bus) — le programme fidélité / codes promo /
/// parrainage n'ont jamais été demandés et n'ont pas de sens pour cet
/// usage. showLoyaltyPromoReferral=false pour "sis" masque ces 3 entrées
/// du menu Profil agent (voir profile_screen.dart) sans toucher aux
/// autres marques.
const bool kShowLoyaltyPromoReferral = bool.fromEnvironment(
  'SHOW_LOYALTY_PROMO_REFERRAL',
  defaultValue: true,
);
