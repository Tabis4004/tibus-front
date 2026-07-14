# Courrier Client — app mobile Flutter

Application dédiée à l'expéditeur/destinataire : suivre un colis (réseau bus
Colis Autonome de Tibus) et, depuis ce suivi, commander une livraison VTC
(dernier kilomètre) via Tibus Ride. Troisième app de la famille Courrier,
aux côtés de `courrier_mobile` (agent) et de l'app livreur VTC (à venir).

## Deux backends, volontairement séparés

Décision produit actée (voir échange de conception) :

- **Tibus principal** (`kqudaqtydimjclwaihqr`) : suivi de colis uniquement,
  mêmes RPC que `courrier_mobile` (`resolve_colis_retrait_code`,
  `get_colis_autonome_detail`). Aucun compte requis.
- **Tibus Ride** (`bjtklpjdsmqmzhncfflu`, projet `tibusride-front`) : commande
  et suivi de la livraison VTC. Base et comptes **séparés** de Tibus
  principal — choix assumé pour aller vite sans toucher à l'existant ni à
  Tibus Ride, plutôt que d'unifier les comptes (migration plus lourde,
  écartée pour l'instant).

Le lien entre les deux systèmes est **fonctionnel, pas un compte partagé** :
le code du colis (`notes` sur la ligne `rides`) permet de retracer quelle
commande VTC correspond à quel colis.

Côté auth Tibus Ride : compte anonyme Supabase (`signInAnonymously`), créé
silencieusement à la première commande — pas d'écran d'inscription séparé.
Si un vrai suivi multi-appareils devient nécessaire, ce compte anonyme
pourra être relié à un numéro de téléphone plus tard (`linkIdentity`), sans
perdre l'historique des commandes.

## Ce que ce scaffold contient déjà

- `TrackColisScreen` : recherche par code, affichage statut/trajet/destinataire.
- Depuis le résultat : bouton "Commander une livraison VTC" → `OrderDeliveryScreen`.
- `OrderDeliveryScreen` : adresses départ/arrivée, véhicule livreur (deux-roues/
  moto/tricycle/voiture/camionnette), type de colis, estimation de prix
  (reprend la grille tarifaire réelle de Tibus Ride —
  `delivery_pricing_settings` + `resolve_dynamic_pricing_settings`).
- `DeliveryStatusScreen` : suivi temps réel (Postgres Realtime sur `rides`) —
  statut, position/ETA du livreur dès qu'assigné, notation en fin de course.
- Le dispatch (proposer la course au livreur le plus proche) est **entièrement
  géré côté base Tibus Ride** (`dispatch_on_ride_insert`) — rien à faire côté
  app après l'insertion dans `rides`.

## Dette technique assumée (v1, pour aller vite)

1. **Pas de carte ni de géocodage d'adresse.** Les coordonnées GPS sont
   capturées via "Utiliser ma position actuelle" (bouton par point), pas par
   saisie d'adresse convertie en lat/lng. Nécessiterait la clé Google Maps
   Geocoding déjà utilisée par `tibusride-front`
   (`GOOGLE_MAPS_API_KEY`/`VITE_GOOGLE_MAPS_BROWSER_KEY`), pas encore branchée
   ici. Fast-follow logique une fois le parcours de bout en bout validé.
2. **Distance à vol d'oiseau** (haversine, même formule que le moteur de
   dispatch côté base), pas de routage réel (Google Directions) — le prix
   affiché est une estimation, peut différer du trajet réel.
3. **`city` non renseigné** : la colonne a un défaut côté base ('Dakar',
   historique EcoMoto Sénégal) — tant qu'aucun géocodage n'est branché, on
   laisse ce défaut s'appliquer plutôt que d'envoyer une valeur fausse. À
   corriger avant un vrai déploiement multi-pays (impacte le matching
   pays/marché du dispatch, voir `dispatch_rank_candidates`).
4. **Paiement** : `payment_method` fixé à `'cash'` pour l'instant — mobile
   money (Orange Money, Wave, MTN/Moov Momo) déjà supporté côté schéma
   (`payment_method` enum), pas encore câblé côté app.
5. **Pas de push natif** pour les mises à jour de livraison (contrairement à
   `courrier_mobile`) — le suivi ne fonctionne qu'app ouverte (Realtime). À
   ajouter si besoin, même schéma que `courrier_mobile/push_service.dart`.

## Pour démarrer

```bash
cd courrier_client
flutter create . --project-name courrier_client --org com.tibus
cp .env.example .env   # renseignez SUPABASE_ANON_KEY et RIDE_SUPABASE_ANON_KEY
flutter pub get
flutter run
```

`RIDE_SUPABASE_ANON_KEY` : clé anon/publishable du projet `bjtklpjdsmqmzhncfflu`
(voir `tibusride-front/.env.example` → `VITE_SUPABASE_PUBLISHABLE_KEY`).
**Ne jamais** utiliser la `SUPABASE_SERVICE_ROLE_KEY` ici — clé anon
uniquement, c'est celle destinée aux apps clientes.

⚠️ `tibusride-front/.env.example` contient actuellement la vraie
`SUPABASE_SERVICE_ROLE_KEY` en clair (pas un placeholder) — si ce fichier a
été poussé sur GitHub, cette clé doit être régénérée depuis le dashboard
Supabase du projet `bjtklpjdsmqmzhncfflu`, indépendamment de ce projet.

## Structure

```
lib/
  core/            thème, config (deux backends), providers
  data/
    models/        ColisSummary, DeliveryRide/RideStatus/DeliveryVehicle
    services/      tibus_backend.dart (colis), ride_backend.dart (VTC)
  features/
    home/           écran d'entrée
    track/          suivi colis + point d'entrée vers la commande VTC
    delivery/       commande + suivi de la livraison VTC
```

## Prochaines étapes suggérées

1. `flutter create .` + test sur appareil (Android d'abord, la géoloc est
   plus simple à tester en physique qu'en simulateur).
2. Géocodage d'adresse réel (Google Places/Geocoding) pour remplacer le
   "utiliser ma position actuelle" par une vraie saisie d'adresse.
3. Câbler `city`/`country` correctement pour le matching multi-pays du
   dispatch (voir dette technique n°3).
4. Mobile money pour le paiement de la livraison.
5. App livreur VTC — troisième pièce de la famille Courrier (à scaffolder).
