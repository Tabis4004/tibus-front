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

## Embarquement — le référentiel des tarifs vit dans Tibus, pas dans le module

Le module Embarquement s'était doté de sa propre table d'itinéraires avec
tarifs (`embarquement_itineraires.price`, migrations 205 et 211). C'était un
doublon : Tibus 1.0 porte déjà exactement cette information, dans
`Gares` (`name`, `cityId`, `companyId`) et surtout
**`ProgrammationTrajetArrets` (`fromGareId`, `toGareId`, `price`)** — soit le
modèle « gare dans une ville → itinéraire gare de départ / gare d'arrivée →
prix ». Toutes les compagnies y sont déjà renseignées.

Depuis la migration 214, ces itinéraires s'administrent **aussi depuis
l'app mobile** (`embarquement_upsert_trajet`, réservé au propriétaire), sans
passer par la billetterie web — l'administration d'Embarquement est autonome,
comme celle de courrier_mobile. Un trajet créé depuis le module naît avec
`isSchedulingActive = false` : il sert à l'embarquement et à la tarification,
il n'est pas mis en vente sans décision explicite côté Tibus.

Depuis la migration 212, `embarquement_itineraires` **est hors circuit** :
elle existe encore en base mais aucune RPC d'Embarquement ne la lit.
`embarquement_list_trajets()` lit `ProgrammationTrajetArrets`, et
`embarquement_open_session_gare()` y relit le tarif pour le figer sur la
session (`embarquement_sessions.fare_amount`).

**Pourquoi c'est structurant, et pas un simple choix d'implémentation.** Le
premier client d'Embarquement exploite une billetterie tierce et a subi une
sous-déclaration de recettes ; le module sert de compteur indépendant, opposé
aux chiffres de cette billetterie. Deux tables de tarifs qui divergent
détruiraient la valeur probante de l'outil. Corollaires à ne pas relitiger
sans nouvelle raison :

- Aucun montant ne transite par le client. `embarquement_scan_external` n'a
  plus de paramètre `p_amount` depuis la migration 212 — il lit
  `embarquement_sessions.fare_amount`. Une version antérieure l'acceptait :
  un APK modifié ou un appel direct à PostgREST avec la clé anon pouvait
  écrire n'importe quelle somme.
- Les changements de tarif sont journalisés avec leur auteur
  (`trajet_arret_price_log`, trigger sur `ProgrammationTrajetArrets`). Ce
  trigger vit sur une table de la billetterie web : il capture
  `current_app_user_id()` dans un bloc `EXCEPTION` pour ne jamais faire
  échouer une vente.
- L'index unique de `ProgrammationTrajetArrets` porte sur
  `(trajetId, fromGareId, toGareId)`, pas sur le seul couple de gares : deux
  trajets distincts peuvent légitimement desservir le même segment (réseau à
  arrêts intermédiaires). Quand deux trajets annoncent des prix différents
  pour un même couple, `embarquement_list_trajets` lève `price_conflict` et
  l'ouverture de session est refusée.

## Embarquement — qui peut ouvrir une session (migration 213)

`can_use_embarquement()` admet **`super_admin`, `owner`, `gerant_gare`,
`controleur_gare`, `comptable_gare`** — et personne d'autre. Les rôles à
portée compagnie (`controleur`, `vendeur`, `chauffeur`) en sont exclus
volontairement : n'étant rattachés à aucune gare, ils pourraient ouvrir une
session sur n'importe quel itinéraire, donc choisir le tarif appliqué à tout
un départ.

`embarquement_sees_all_gares()` ne renvoie vrai que pour `super_admin` et
`owner`. Les trois rôles de gare ne voient que les itinéraires partant de
leur `UserRoles.gareId` — même règle que `list_company_station_gares()`
(migration 198), déjà en place côté Colis.

Côté Flutter, `AppRole.isEmbarquementRole` et `_rolePriority`
(`embarquement/lib/core/providers.dart`) doivent rester le miroir exact de
`can_use_embarquement()`. Le serveur seul fait autorité ; ces listes servent
uniquement à ne pas proposer une compagnie dont toutes les RPC refuseraient
l'accès.

Depuis la migration 214, `embarquement_permissions` peut ouvrir le module à un
rôle de gare supplémentaire, gare par gare. Deux règles appliquées côté
serveur, la seconde étant la plus importante : le gérant n'accorde que sur SA
gare, et qu'à un rôle de niveau **strictement inférieur** au sien — sinon la
délégation deviendrait une escalade de privilèges. Seuls les rôles en
`%_gare` sont éligibles ; accorder à un rôle à portée compagnie rouvrirait
exactement ce que la migration 213 a fermé.
