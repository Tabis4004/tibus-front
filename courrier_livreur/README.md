# Courrier Livreur — app chauffeur VTC (Flutter)

Troisième et dernière app de la famille Courrier, aux côtés de
`courrier_mobile` (agent) et `courrier_client` (expéditeur/destinataire).
Réécriture **Flutter native** de l'espace chauffeur/livreur web de Tibus Ride
(`tibusride-front/src/routes/_authenticated/app/driver.tsx`) — décision
produit actée (pas de reprise telle quelle du code React/Capacitor).

## Backend

Un seul backend : **Tibus Ride** (`bjtklpjdsmqmzhncfflu`, projet
`tibusride-front`). Cette app ne parle jamais au Supabase Tibus principal.
`driver_profiles.partner_type` est toujours forcé à `'delivery'` — livraison de
colis en capacité principale. Depuis la tâche #28, un livreur peut en plus
activer une capacité secondaire "transport de passagers (VTC)"
(`passenger_rides_status`/`assigned_ride_category`), soumise à validation
admin ; voir "Dette technique" point 7 pour ce qui manque encore côté
réception effective de courses passagers.

## Ce que ça fait

- **Auth** : email + mot de passe (`signUp` avec `role: 'driver'` en
  métadonnées → trigger `handle_new_user` côté base crée automatiquement
  `profiles` + `user_roles('driver')` + `driver_profiles`).
- **En attente de validation** : tant que `driver_profiles.status != 'approved'`,
  écran dédié — infos véhicule de base éditables, validation finale par un
  admin (back-office web).
- **En ligne / hors ligne** + signalement de position toutes les ~10s
  (`LocationReporter`), condition nécessaire au dispatch par proximité.
- **Deux modes de dispatch**, gérés en parallèle comme côté web
  (`market_programs.dispatch_mode` par pays) :
  - **proximity** : offre poussée un livreur à la fois (`ride_offers` +
    RPC `accept_ride_offer`/`decline_ride_offer`), compte à rebours, adresse
    et prix masqués tant que l'offre n'est pas acceptée (confidentialité,
    même choix que le web).
  - **self_assign** : liste ouverte des livraisons `requested`, acceptation
    par verrou optimiste (`update ... where status = 'requested'`).
- **Livraison active** : boutons de progression (`accepted → arriving →
  in_progress → completed`), position transmise en direct au client
  (`rides.driver_lat/lng`), appel/WhatsApp destinataire, lien Google Maps.
- **Wallet** : solde + historique des mouvements (lecture directe, RLS déjà
  scopée). Rappel si solde épuisé (bloque l'acceptation, appliqué côté base).
- **Notes reçues**.

## Dette technique assumée (v1, pour aller vite)

1. **Pas de dossier d'enrôlement complet** (permis, carte grise, photos
   véhicule pour contrôle physique) contrairement à `EnrollmentWizard` côté
   web — juste type de véhicule/immatriculation/ville. Validation finale
   toujours manuelle par un admin.
2. **Pas de position en arrière-plan** : la position n'est transmise que tant
   que l'app est au premier plan (pas de service natif background location).
3. **Pas de zone d'opération éditable** (`driver_zones`) — un livreur sans
   zone définie reçoit des offres partout dans son pays (comportement déjà
   correct par défaut côté moteur de dispatch).
4. **Pas de frais d'attente** (`waiting_started_at`/`waiting_fee_xof`), pas de
   carte embarquée (lien Google Maps externe uniquement), pas de
   statistiques financières détaillées (graphiques/export CSV côté web).
5. **Pas d'OTP téléphone** — email + mot de passe uniquement, même si
   `country_market_config.auth_phone_otp` le permettrait pour certains pays.
6. **Pas de notifications push natives** pour les nouvelles offres — l'app
   doit être ouverte (polling toutes les 3-4s), voir `push_service.dart` de
   `courrier_mobile` pour le schéma à reprendre si besoin.
7. **VTC (tâche #28) : phases 1 et 2 faites.** Toggle auto-service +
   validation admin + moteur de dispatch + réception d'offres/liste ouverte
   + écran de trajet passager en cours sont tous en place, aussi bien pour
   le mode proximity (offres poussées) que self_assign (liste ouverte,
   restreinte à la catégorie approuvée du livreur). Pas de notifications
   push natives spécifiques aux courses passager (même limite générale que
   le point 6 ci-dessus).

## Pour démarrer

```bash
cd courrier_livreur
flutter create . --project-name courrier_livreur --org com.tibus
cp .env.example .env   # renseignez RIDE_SUPABASE_ANON_KEY
flutter pub get
flutter run
```

`RIDE_SUPABASE_ANON_KEY` : clé anon/publishable du projet `bjtklpjdsmqmzhncfflu`
(voir `tibusride-front/.env.example` → `VITE_SUPABASE_PUBLISHABLE_KEY`).
**Ne jamais** utiliser la `SUPABASE_SERVICE_ROLE_KEY` ici.

## Structure

```
lib/
  core/            thème, config (backend Tibus Ride), providers (Riverpod)
  data/
    models/        DriverProfile, ActiveRide/OpenDelivery/PendingOffer/RideStatus
    services/      driver_backend.dart (tout l'accès Supabase)
  features/
    auth/           connexion / inscription
    onboarding/     écran "en attente de validation"
    home/           dashboard (toggle en ligne, offres, liste ouverte, course active), location_reporter
    offers/         cartes offre poussée / liste ouverte
    ride/           écran de pilotage d'une livraison active
    wallet/         solde + mouvements
    profile/        infos compte, notes reçues, déconnexion
```

## Prochaines étapes suggérées

1. `flutter create .` + test sur appareil Android (permissions GPS réelles).
2. Dossier d'enrôlement complet (upload permis/carte grise/photos) si le
   volume de recrutement via mobile le justifie.
3. Position en arrière-plan (service natif) pour ne pas perdre le dispatch
   par proximité quand l'app est minimisée.
4. Notifications push natives pour les nouvelles offres (FCM, comme
   `courrier_mobile`).
5. Frais d'attente + carte embarquée, si l'usage le demande.
