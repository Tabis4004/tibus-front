# Tibus — notes d'architecture (à lire avant toute intervention)

## Deux bases Supabase distinctes — ne jamais les confondre

Ce monorepo héberge plusieurs apps qui utilisent **deux projets Supabase
différents et volontairement séparés**. C'est une source de confusion
récurrente (URL/clé mélangées entre les deux) — vérifié et confirmé en
direct le 2026-07-26, à ne pas relitiger sans nouvelle preuve.

### 1. `kqudaqtydimjclwaihqr.supabase.co` — "Tibus 1.0"
Base principale de la plateforme de bus Tibus (billetterie, gares,
compagnies, Colis Autonome...). Tables en PascalCase (`Users`, `UserRoles`,
`Bus`, `Companies`, `Gares`, `ReservationBus`, `colis_autonomes`,
`bordereau_colis`...). Fonctions `register_colis_autonome`,
`list_colis_autonomes`, etc.

**Utilisée par : `courrier_mobile` uniquement** (app agent/guichet de
gestion de colis, dérivée du module Colis Autonome — voir
`courrier_mobile/README.md`).

### 2. `bjtklpjdsmqmzhncfflu.supabase.co` — "Tibus Ride" / "Tibus Drive"
Base du système VTC (`tibusride-front`, prod :
https://tibusride-front.vercel.app). Tables `driver_profiles`, `rides`,
`market_programs`, fonction `dispatch_rank_candidates`, etc. Confirmée
comme la base officielle de Tibus Ride via `tibusride-front/.env.example`
(source de vérité — ne pas déduire l'URL autrement).

**Utilisée par : `courrier_livreur` et `courrier_client`** — ces deux apps
sont des duplicata/extensions de Tibus Ride (chauffeur + passager), pas de
la plateforme bus. Elles doivent utiliser la même URL + même clé anon que
`tibusride-front`.

### Piège vécu
`courrier_client/lib/main.dart` a eu l'URL `kqudaqtydimjclwaihqr` avec la
clé anon de `bjtklpjdsmqmzhncfflu` (mismatch projet/clé → tous les appels
Supabase échouent, y compris le login). Toujours vérifier que l'URL et la
clé anon d'un `Supabase.initialize(...)` appartiennent au **même** projet
(décoder le payload JWT de la clé : le champ `ref` doit correspondre au
sous-domaine de l'URL).

## Accès MCP Supabase de l'agent
Le MCP Supabase connecté par défaut ne voit que "Tibus 1.0"
(`kqudaqtydimjclwaihqr`) et "TabisPay" (`lxgzgkeibtqfuzpjizrv`, inactif) —
**pas** `bjtklpjdsmqmzhncfflu`. Pour toute migration/requête touchant au
VTC (driver_profiles, rides, dispatch...), l'utilisateur doit reconnecter
l'accès à ce projet spécifiquement.

## `web/` est gitignored dans les 3 apps Flutter (courrier_client,
courrier_livreur, courrier_mobile)
Traité à tort comme un dossier "généré" (comme `android/`/`ios/`). Les
éditions directes de `web/index.html`, `web/manifest.json`, favicons etc.
ne sont donc **jamais** commitées/déployées. Le contournement en place est
`branding/webassets/` (suivi par git) que chaque `vercel-build.sh` recopie
par-dessus le `web/` régénéré par `flutter create` à chaque build Vercel.
Toute modification de branding web doit passer par `branding/webassets/` +
la logique de copie dans `vercel-build.sh`, jamais par une édition directe
de `web/` seule.

## AndroidManifest release vs debug
Flutter ne met la permission `INTERNET` que dans
`android/app/src/debug/AndroidManifest.xml` par défaut — **absente** du
manifest `main` (release). Un `flutter build apk --release` sans cette
permission ajoutée manuellement au manifest `main` n'a aucun accès réseau
(symptôme : "impossible de se connecter" alors que tout fonctionne en
debug). Vérifié comme faux sur les 3 apps le 2026-07-26, corrigé.
