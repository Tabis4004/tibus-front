# Embarquement

Module Flutter autonome (dossier séparé, comme `courrier_mobile/`) : scan de
billets Tibus et de QR tiers, manifeste et rapport d'embarquement. Backend
intégré au projet Supabase Tibus 1.0 (`kqudaqtydimjclwaihqr`) — voir
`../CLAUDE.md` et `../plan_module_embarquement_v2.md` à la racine du dépôt
pour l'architecture complète et le phasage.

## Ce dossier ne contient pas encore les plateformes natives

Contrairement à `courrier_mobile/`, ce module a été scaffoldé sans accès à un
SDK Flutter (créé par un agent dans un environnement sans Flutter). Avant de
lancer l'app, exécuter une fois en local :

```bash
cd embarquement
flutter create . --org com.tibus --project-name embarquement
flutter pub get
```

`flutter create .` régénère les dossiers `android/`, `ios/`, `web/` (déjà
dans `.gitignore`, aucun code natif custom ici contrairement à
`courrier_mobile/android`) sans toucher au code Dart déjà écrit dans `lib/`.

## État (Phase 0 — fondations)

- [x] Connexion Supabase (même projet que Tibus 1.0, `lib/core/config/env.dart`)
- [x] Auth réutilisant les comptes Tibus existants (`lib/features/auth/`)
- [x] Liste des sessions Embarquement (`lib/features/session/`) — RPC
      `embarquement_list_sessions`/`embarquement_create_session` déjà en
      place côté serveur
- [x] Référentiel hors-Tibus — itinéraires + bus (`lib/features/referentiel/`)
      — RPC ajoutées migration
      `../supabase/migrations/205_embarquement_referentiel_itineraires_bus.sql`
- [ ] Phase 1 — scan Tibus (`list_embarquement_departures`,
      `embarquement_scan_tibus`, pas encore de RPC serveur)
- [ ] Phase 2 — scan QR externe (parseur multi-format)
- [ ] Phase 3 — manifeste temps réel
- [ ] Phase 4 — rapport & clôture (no-show, export)
- [ ] Phase 5 — durcissement (permissions fines, mode hors-ligne)

Voir `../plan_module_embarquement_v2.md` pour le détail de chaque phase.
