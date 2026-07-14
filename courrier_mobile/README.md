# Courrier — app mobile Flutter

Application mobile native (Flutter/Dart) dédiée au suivi et à la gestion de
colis, dérivée du module **Colis Autonome** de Tibus. Décision produit
actée : **adapter la base Supabase existante** (pas de nouvelle base), pour
éviter tout risque de perte de données ou de comptes utilisateurs, avec la
possibilité de migrer un jour vers une base séparée si le besoin apparaît.

Voir `Etude_Faisabilite_Courrier.docx` (à la racine du dossier Tibus) pour
l'analyse complète du périmètre.

## Ce que ce scaffold contient déjà

- Thème et composants visuels calqués sur les maquettes de référence
  (accueil, liste des colis, statistiques, navigation basse à 5 entrées).
- Écrans **agent** (vendeur / gérant de gare / owner / admin) : accueil,
  liste + recherche + filtres, création, détail avec avancement de statut,
  statistiques.
- Écrans **client** (expéditeur/destinataire) : suivi d'un colis par code
  sans compte, fidélité, codes promo, parrainage.
- Couche `data/services/*` qui appelle **exactement** les RPC déjà en
  production côté Tibus (`register_colis_autonome`, `list_colis_autonomes`,
  `get_colis_autonome_detail`, `update_colis_autonome_statut`,
  `deliver_colis_autonome`, `resolve_colis_retrait_code`,
  `get_company_colis_settings`, `get_traveler_loyalty_context`,
  `validate_loyalty_redemption`, `list_owner_promo_codes`). Rien n'est
  réécrit côté base pour ces fonctions.
- Modèle de rôles conservé à l'identique (`Role` / `UserRoles`), interrogé
  directement depuis `AuthService.fetchMyRoles()`.

## Pour démarrer

Ce dossier ne contient volontairement pas les projets natifs Android/iOS
(non générés dans cet environnement, pas de SDK Flutter disponible ici).
Sur votre machine, avec Flutter installé :

```bash
cd courrier_mobile
flutter create . --project-name courrier --org com.tibus   # génère android/ ios/ web/...
cp .env.example .env                                        # déjà pré-rempli avec le projet Supabase existant
flutter pub get
flutter run
```

`flutter create .` ne touche pas au dossier `lib/` existant : il ne fait
que compléter les dossiers de plateforme manquants.

## Notifications push natives (FCM) — comment avancer

Le code est déjà en place des deux côtés : `PushService` (permission, token,
premier plan/arrière-plan), `ColisService.subscribeToTracking` /
`notifyColisStatusChange`, la table `DeviceTokens` et
`ColisTrackingSubscriptions` (migrations appliquées sur Tibus 1.0), et
l'edge function `supabase/functions/send-colis-push`. Ce qui manque ne peut
être fait que par vous, car ça nécessite vos propres comptes développeur :

**A. Créer le projet Firebase (obligatoire, gratuit, ~10 min)**
1. Allez sur [console.firebase.google.com](https://console.firebase.google.com),
   connectez-vous avec votre compte Google, cliquez "Ajouter un projet" —
   nommez-le par exemple "Courrier".
2. Une fois `flutter create .` exécuté chez vous (étape "Pour démarrer"
   ci-dessus), installez les outils :
   ```bash
   npm install -g firebase-tools
   firebase login
   dart pub global activate flutterfire_cli
   ```
3. À la racine de `courrier_mobile` :
   ```bash
   flutterfire configure
   ```
   Choisissez le projet Firebase créé à l'étape 1, cochez Android et iOS.
   Cette commande génère automatiquement `lib/firebase_options.dart` (celui
   du repo est un placeholder, prévu pour être remplacé) et enregistre vos
   apps Android/iOS dans Firebase — pas de manipulation manuelle de
   `google-services.json` nécessaire.

**B. Pour iOS uniquement — nécessite un compte Apple Developer (payant,
99 $/an)**
1. Sur [developer.apple.com](https://developer.apple.com), créez une clé
   d'authentification APNs (Certificates, Identifiers & Profiles > Keys).
2. Dans Firebase Console > Paramètres du projet > Cloud Messaging > 
   configuration Apple, importez cette clé (.p8) avec son Key ID et votre
   Team ID.
   Sans cette étape, le push fonctionne sur Android mais pas sur iOS.

**C. Permettre à Supabase d'envoyer les notifications (côté serveur)**
1. Firebase Console > Paramètres du projet > Comptes de service > "Générer
   une nouvelle clé privée" — télécharge un fichier `.json`.
2. Définissez-le comme secret Supabase (jamais dans le code ni sur GitHub) :
   ```bash
   supabase secrets set FCM_SERVICE_ACCOUNT="$(cat chemin/vers/la-cle.json)" \
     --project-ref kqudaqtydimjclwaihqr
   ```
3. Déployez l'edge function (je peux le faire directement si vous préférez,
   j'ai un accès au projet Supabase) :
   ```bash
   supabase functions deploy send-colis-push --project-ref kqudaqtydimjclwaihqr
   ```

Tant que A/B/C ne sont pas faits, l'app continue de fonctionner normalement
avec le suivi Supabase Realtime (notification uniquement app ouverte) —
rien n'est bloquant.

## Impression de reçu (imprimante P3/Wiseasy intégrée)

Sur les terminaux Android dédiés (POS Wiseasy CS10/P3, mêmes appareils que
`tibus-v2-HUB`), Courrier peut imprimer un reçu de colis sur l'imprimante
thermique intégrée — sans dépendance à une imprimante externe.

Ce qui a été repris **tel quel** de `tibus-v2-HUB` (même SDK Wangpos, même
logique de rendu du ticket) :
- `android/app/libs/` : `PrinterSDKLibV03.02.04.jar`, `CS10-C-SDK-v1.1.6.aar`,
  `SDK4BaseBinderV2.2.12.jar` (SDK fabricant, ne pas supprimer).
- `android/app/src/main/kotlin/com/tibus/courrier/printer/P3PrinterModule.kt` :
  copie fidèle de `P3PrinterModule.kt` (driver Wangpos réellement utilisé en
  production côté Tibus web — pas le squelette `WisePrinterModule`, qui
  n'était jamais branché). Seul le package a changé.

Ce qui est nouveau, propre à Courrier (Flutter n'a pas de WebView à ponter) :
- `P3PrinterChannel.kt` : expose le driver via un `MethodChannel` Flutter
  (`com.tibus.courrier/p3_printer`) au lieu d'un pont JavaScript WebView.
- `lib/data/services/printer_service.dart` : appelle ce canal côté Dart.
  `PrinterService.isAvailable` est `false` sur iOS/web/tout appareil sans ce
  hardware — les appels sont alors no-op ou lèvent une erreur explicite,
  jamais un crash silencieux.
- Bouton d'impression (icône imprimante) sur `ColisDetailScreen`, qui appelle
  `printerService.printColisReceipt(colis)`.

Rien à configurer : ça fonctionne dès que l'app tourne sur un Wiseasy
CS10/P3 (`flutter run` avec l'appareil connecté, ou l'APK installé).

## Dette technique identifiée

Parité front Courrier ↔ Tibus web actée : toute évolution du module Colis
Autonome côté web (`src/pages/seller/ColisAutonomesPage.tsx`,
`src/lib/supabase/colis-autonomes.ts`) doit être répercutée ici, et
inversement — les deux apps consomment les mêmes RPC/tables Supabase.

### Résolu

1. ✅ **Sélection de gares** dans `ColisCreateScreen` : branchée sur
   `list_company_station_gares` (même RPC que le sélecteur web). La gare de
   départ est verrouillée sur la gare de la caisse ouverte de l'agent — la
   base l'exige de toute façon (`assert_seller_cash_departure_gare`), donc
   il n'y a pas de vente cash possible depuis une autre gare.
2. ✅ **Sélection de nature de colis** : branchée sur `ColisService.listNatures`
   (déjà existant, jamais appelé depuis l'écran de création). Le seuil
   minimum par nature (`get_colis_prix_min`) est aussi affiché et vérifié
   côté client, en plus du blocage serveur.
3. ✅ **Valeur marchandise obligatoire + pourcentage perçu** : alignés sur le
   web (voir migration `colis_pourcentage_percu` sur le projet Supabase
   Tibus 1.0) — champ obligatoire, calcul automatique du montant fret
   optionnel, notifications WhatsApp à chaque étape du suivi (`Colis
   Detail Screen` + reçu imprimé).
4. ✅ **Push FCM — parties A et C terminées.** Edge function `send-colis-push`
   déployée sur le projet Supabase (partie C). Projet Firebase `tibus-courrier`
   configuré via `flutterfire configure` (partie A) : `firebase_options.dart`
   contient les vraies clés Android/iOS, `android/app/google-services.json`
   et `ios/Runner/GoogleService-Info.plist` présents, secret
   `FCM_SERVICE_ACCOUNT` tourné et l'ancienne clé de service Firebase
   révoquée. **Android est donc pleinement opérationnel pour le push.** Seule
   la **partie B (compte Apple Developer + clé APNs)** reste ouverte —
   nécessaire uniquement pour le push sur iOS, voir point 8.
5. ✅ **Caisse gérable depuis Courrier.** Nouvel écran `StationCashScreen`
   (`lib/features/agent/caisse/`), accessible depuis l'accueil ("Ma caisse")
   et depuis `ColisCreateScreen` quand aucune caisse n'est ouverte. Réplique
   exactement `StationCashPanel.tsx` (web) : ouverture (gare + fond de
   roulement), solde temps réel + journal des mouvements, soumission du
   reversement de fin de service. Mêmes RPC des deux côtés
   (`open_station_cash_register`, `list_station_cash_movements`,
   `submit_station_cash_reversal`). Seule la **validation** du reversement
   (rôle comptable/owner) reste web-only — aucun rôle `comptable_gare` n'est
   géré dans Courrier pour l'instant ; à ajouter si des comptables doivent
   aussi travailler depuis mobile.
6. ✅ **Points fidélité crédités sur les colis, au taux défini sur Tibus.**
   Nouvelle fonction base `process_loyalty_on_colis`, appelée automatiquement
   par `register_colis_autonome` (donc active des deux côtés sans rien
   changer au front) : si le téléphone de l'expéditeur correspond à un
   compte `Users` existant, elle crédite des points selon
   `CompanyLoyaltySettings.spendUnitAmount` / `pointsPerSpendUnit` — le même
   réglage que celui déjà configuré par l'owner pour les billets sur Tibus
   web, aucune nouvelle config à faire. Best-effort : ne bloque jamais
   l'enregistrement d'un colis (expéditeur sans compte, programme inactif,
   etc. → silencieusement ignoré). La *dépense* de points sur un colis
   (payer un envoi avec des points) n'est pas branchée côté UI — voir point
   10 ci-dessous si c'est souhaité.
7. ✅ **Scan colis + manifeste avec filtres**, alignés sur le web. Nouvel
    écran `ColisScanScreen` (`lib/features/agent/colis/colis_scan_screen.dart`,
    accessible depuis l'accueil et la liste des colis) : scan caméra
    (`mobile_scanner`, déjà en dépendance) ou saisie manuelle de la référence
    `CL-XXXXXXXX`, puis avancement du statut en un clic — mêmes 3 étapes que
    `ColisScanWorkflow.tsx` (en soute → arrivé → remis), `update_colis_autonome_statut`
    pour les deux premières transitions, `deliver_colis_autonome` pour la
    remise finale. Permission caméra ajoutée (`AndroidManifest.xml` +
    `NSCameraUsageDescription` iOS). Nouvel écran `ColisManifestScreen`
    (`colis_manifest_screen.dart`) : mêmes statistiques (envois, total fret)
    et filtres (statut, gare départ, gare destination, dates) que l'onglet
    "Colis autonomes" de `owner/analytics/SupabaseTripReports.tsx`, filtrage
    100 % client sur `list_colis_autonomes` (`limit: 500`, identique au web)
    faute de RPC de stats dédiée. Export CSV via `share_plus` (feuille de
    partage native — mail, WhatsApp, Drive...) plutôt qu'un export PDF façon
    `jsPDF`, non répliqué côté mobile pour rester léger.
12. ✅ **Bus du convoi sur les colis** (migration `colis_bus_convoi` sur le
    projet Supabase). Colonne `colis_autonomes.bus_id` (FK `Bus`), exposée
    dans `list_colis_autonomes`/`get_colis_autonome_detail` (`busId`,
    `busPlateNumber`), assignable dès l'enregistrement (`register_colis_autonome`,
    param optionnel) ou au passage "Chargé" (`update_colis_autonome_statut`,
    param optionnel — ne touche pas au bus déjà assigné si omis). Lecture de
    la liste des bus actifs via un select direct sur la table `Bus`
    (`ColisService.listBuses`, RLS `bus_select` déjà publique pour les
    compagnies actives — même accès que `listCompanyBusesSupabase` côté web,
    pas besoin de nouvelle RPC). Sélecteur de bus affiché dans
    `ColisScanScreen` et `ColisDetailScreen` uniquement à la transition
    "Charger en soute" ; filtre "Bus" ajouté dans `ColisManifestScreen` (et
    dans l'export CSV) ainsi que côté web dans l'onglet Suivi de
    `ColisAutonomesPage.tsx` et le manifeste owner `SupabaseTripReports.tsx`.

### Encore ouvert

8. **Statistiques colis** : toujours agrégées côté client dans
   `StatsService` à partir de `list_colis_autonomes` (`limit: 1000`).
   Fonctionne correctement au volume actuel — pas d'action requise tant que
   la liste ne devient pas trop volumineuse pour ce calcul client.
9. **Notifications push natives (FCM) — partie B seule reste ouverte.**
   Compte Apple Developer (99$/an) + clé d'authentification APNs à générer
   et uploader dans Firebase Cloud Messaging (onglet iOS app configuration).
   Nécessaire uniquement pour que le push fonctionne sur iOS — Android est
   déjà pleinement fonctionnel (voir point 4).
10. **Dépense de points / codes promo sur les colis** :
   - `validate_loyalty_redemption` est générique (malgré son paramètre
     `p_ticket_price`) et fonctionnerait déjà avec `montant_fret` d'un colis
     — rien à ajouter côté base si vous voulez permettre à un client de
     payer (une partie de) son envoi avec ses points. Reste à construire :
     l'UI (web + mobile) pour saisir/afficher ce choix au guichet.
   - Les codes promo (`apply_promo_code_to_colis`) n'existent nulle part, ni
     web ni mobile — `list_owner_promo_codes` ne gère que la création par
     l'owner, pas l'application côté vente. À construire des deux côtés si
     retenu. `PromoService.applyPromoCodeToColis` reste un
     `UnimplementedError` explicite en attendant cette décision.
11. **Comptes / mots de passe** : l'app réutilise Supabase Auth tel quel
    (mêmes comptes que Tibus, mêmes rôles) — aucune migration de compte à
    prévoir, rien à faire ici.

## Structure

```
lib/
  core/            thème, config, router, widgets partagés
  data/
    models/        Colis, AppRole, LoyaltyContext, PromoCode...
    services/       tout l'accès Supabase (RPC + tables), rien d'autre n'appelle Supabase directement
  features/
    auth/           connexion
    agent/          home, colis (liste/création/détail), stats, profil
    client/         suivi colis, fidélité, promo, parrainage
    shell/          navigation basse (bottom nav + FAB central)
```

## Prochaines étapes suggérées

1. `flutter create .` + `flutter pub get` (nouvelles dépendances
   `url_launcher` pour WhatsApp et `share_plus` pour l'export du manifeste)
   + test sur un appareil/émulateur.
2. Tester le flux complet sur un compte vendeur/vendeur_gare : ouvrir la
   caisse depuis l'écran "Ma caisse", enregistrer un colis (gares/natures/
   valeur marchandise), vérifier le crédit de points si l'expéditeur a un
   compte, soumettre un reversement en fin de session, scanner un colis pour
   le faire avancer (accueil → "Scanner un colis"), consulter/filtrer/
   exporter le manifeste (accueil → "Manifeste colis").
3. Décider si la dépense de points ou les codes promo doivent être
   branchés sur les colis (dette #9) — la base est prête pour les points,
   pas pour les codes promo.
4. Suivre les étapes A/B de la section "Notifications push natives (FCM)"
   ci-dessus dès que vous voulez le push réellement en arrière-plan — la
   partie C (edge function) est déjà déployée.
5. Pousser ce dossier sur GitHub (`git remote add origin ... && git push -u origin main`) —
   l'historique git est déjà initialisé localement.
