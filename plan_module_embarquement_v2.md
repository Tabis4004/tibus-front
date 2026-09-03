# Module « Embarquement » — plan de travail (v2, vérifié sur le code réel)

## 0. Architecture retenue (tranchée avec l'utilisateur)

- **Backend** : intégré à Tibus 1.0, même projet Supabase (`kqudaqtydimjclwaihqr`) que
  `tibus-front` et `courrier_mobile`. Réutilise les tables et RPC existantes plutôt
  que de les recréer.
- **Frontend** : projet Flutter **autonome**, dossier séparé au même niveau que
  `courrier_mobile/` (pas un onglet dans une app existante) — écrans, modèles et
  services propres à Embarquement.
- **Portabilité future** : le client a explicitement demandé la possibilité de
  migrer la base d'UNE compagnie vers son propre serveur plus tard, à sa demande.
  C'est déjà un pattern établi dans ce dépôt (`courrier_mobile/tool/hostinger_migration/`,
  et un trigger `block_sis_client_writes()` bloque déjà les écritures d'une
  compagnie migrée — vérifié en direct sur la base de prod pendant cette session).
  Conséquence pour le schéma Embarquement : éviter les FK profondes vers les
  tables Tibus 1.0 quand un champ texte dénormalisé suffit (le schéma déjà
  esquissé par l'autre session dans `files.zip` avait raison sur ce point précis
  — `tibus_reservation_reference text` plutôt qu'une FK vivante — cette partie-là
  est reprise ; le reste de ce schéma autonome, en revanche, n'est PAS retenu ici
  car il duplique inutilement Companies/Gares/Bus/UserRoles qui existent déjà.

## 1. Divergence trouvée entre les deux documents fournis, et comment elle est tranchée

`plan_module_embarquement.md` (fourni par l'autre session) et `files.zip` (schéma
SQL fourni par la même session) proposaient deux architectures incompatibles :
le premier réutilise Tibus 1.0 en interne, le second reconstruit un backend
multi-tenant autonome (ses propres `companies`/`users`/`gares`/`buses`, vérification
Tibus uniquement via appel HTTP public). Tranché avec l'utilisateur : **on suit
le premier document** (intégration), le second reste une référence utile pour le
jour où une compagnie demandera une vraie migration de sa base.

## 2. Ce qui est vérifié comme réutilisable tel quel (lu dans le code, pas supposé)

| Besoin | Source vérifiée | Détail |
|---|---|---|
| Vérifier + enregistrer l'embarquement d'un billet Tibus | RPC `verify_ticket_qr(p_reference, p_token, p_record_boarding, p_manual_reference, p_scanner_company_id)` (migration 117) | Un seul appel avec `p_record_boarding = true` vérifie ET marque `boardedAt` en une fois — voir §6, nuance boardedAt/onBoardAt |
| Confirmation « à bord » (étape 2, optionnelle) | RPC `confirm_passenger_on_board(p_reference, p_scanner_company_id)` | Marque `onBoardAt`, distinct de `boardedAt` |
| Portée compagnie du scanner | `resolve_scanner_company_id` (server-side, déjà appelée par `verify_ticket_qr`) + résolution client `resolveScannerCompanyId()` (`src/lib/supabase/scanner-company.ts`) — lit `UserRoles` join `Role`, repli localStorage pour un owner multi-compagnies | Logique simple (une requête sur `UserRoles`), à porter en Dart, pas besoin de dupliquer le fichier TS |
| Garde inter-compagnies | `ticket_matches_scanner_company` | Déjà appelée en interne par `verify_ticket_qr`, rien à faire côté client |
| Parser une URL/QR Tibus | `parseTicketQrPayload()` (`src/lib/ticket-verify-url.ts`) | ~30 lignes, à porter en Dart telles quelles (URL avec `t=` token, ou regex `TB-[A-Z0-9]+` en repli) |
| Code couleur du résultat | `resolveTone()` (`TicketScanResult.tsx`) | `on_board` → rouge, `valid` → vert, `duplicate` → orange, tout le reste → rouge |
| Départs programmés Tibus (places, bus, capacité) | `listOwnerDeparturesSupabase()` (`src/lib/supabase/owner-trips.ts`) → type `OwnerDeparture { totalSeats, seatsAvailable, seatsBooked, origin, destination, bus, departureTime }` | Logique multi-requêtes (Reservations + ProgrammationTrajets + Bus) trop lourde à reporter telle quelle en Dart → **prévoir une RPC dédiée fine** côté serveur qui renvoie directement ce JSON (voir §4) |
| Style d'export manifeste | `trip-manifest-export.ts` | Colonnes : Nom passager, N° billet, Gare départ, Bagages, Statut réservation, Contrôle scan, Embarquement (case à cocher) — à adapter avec une colonne Source (tibus/externe/manuel) |
| Gate feature-module scanner | `useCompanyFeatureModules(companyId).hasModule("B")` bloque le scanner web si le module B n'est pas actif pour la compagnie | **Tranché : non réutilisé.** Embarquement est un module indépendant, vendable/activable séparément du module B du scanner web — pas de `hasModule("B")` dans `_assert_embarquement_access`. |

Rien de tout ça n'est dupliqué dans le nouveau schéma — Embarquement les appelle.

## 3. Nuance importante découverte : deux étapes d'embarquement dans Tibus 1.0 — TRANCHÉ

Le scanner web actuel a en réalité **deux champs distincts** sur `ReservationBus` :
`boardedAt` (posé par `verify_ticket_qr(..., p_record_boarding=true)`, au scan)
et `onBoardAt` (posé par `confirm_passenger_on_board`, bouton séparé « confirmer à
bord »). Le plan initial supposait un scan = un embarquement en une étape.

**Décision utilisateur : une seule étape.** Scan = passager marqué embarqué
immédiatement (`p_record_boarding=true`, jamais d'appel à
`confirm_passenger_on_board`). Cohérent avec « un scan = une ligne au manifeste ».

**Clarification importante liée (remarque terrain de l'utilisateur) : le QR
Tibus lui-même ne contient QUE la référence du billet (+ un token optionnel)
— vérifié dans `parseTicketQrPayload()`, aucune donnée passager n'est encodée
dans le QR. Le nom, la gare de départ/destination et la date du billet à
mettre sur le manifeste ne viennent PAS du contenu du QR : ils viennent de la
réponse de `verify_ticket_qr()`, appelée côté serveur juste après avoir extrait
la référence du QR. C'est déjà exactement le design retenu au §4
(`embarquement_scan_tibus` appelle `verify_ticket_qr` en interne et récupère
`passengerName`/`origin`/`destination`/`trip` pour remplir `passenger_name`,
`origin_label`, `destination_label` sur la ligne de scan) — aucun changement de
schéma nécessaire, seulement à garder explicite pour l'implémentation : le
scan QR Tibus est une étape d'extraction de référence, pas de lecture directe
des infos passager.**

## 4. Schéma SQL à ajouter (intégré à `kqudaqtydimjclwaihqr`, pas de nouvelle base)

Cinq tables, scopées par `company_id` comme le reste de l'app, suivant
exactement le pattern déjà utilisé pour `bordereaux_livraison` /
`colis_autonomes` (RLS activée, accès uniquement via RPC `SECURITY DEFINER`).
Deux d'entre elles (`embarquement_itineraires`, `embarquement_buses`) forment
le **référentiel hors-Tibus dès la V1** (décision utilisateur — pas de saisie
libre à chaque session) : propres à Embarquement, sans toucher/dupliquer
`Gares`/`Bus`/`ProgrammationTrajets` de Tibus 1.0, pour ne pas polluer la
billetterie — un transporteur sans billetterie Tibus peut ainsi déclarer ses
itinéraires et bus une fois, puis les réutiliser à chaque session.

```sql
-- Référentiel hors-Tibus (V1) — créé/géré une fois par un admin (owner/
-- super_admin), réutilisé à chaque ouverture de session hors-Tibus.
CREATE TABLE embarquement_itineraires (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES "Companies"(id) ON DELETE CASCADE,
  origin_label text NOT NULL,
  destination_label text NOT NULL,
  active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX embarquement_itineraires_company_idx ON embarquement_itineraires(company_id) WHERE active;

CREATE TABLE embarquement_buses (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES "Companies"(id) ON DELETE CASCADE,
  label text NOT NULL,               -- ex: "Bus 12 - AB-1234-CI"
  capacity integer NOT NULL CHECK (capacity > 0),
  active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX embarquement_buses_company_idx ON embarquement_buses(company_id) WHERE active;

CREATE TABLE embarquement_sessions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES "Companies"(id) ON DELETE CASCADE,
  reservation_id uuid REFERENCES "Reservations"(id) ON DELETE SET NULL, -- NULL si hors-Tibus
  itineraire_id uuid REFERENCES embarquement_itineraires(id) ON DELETE SET NULL, -- hors-Tibus, référentiel
  bus_id uuid REFERENCES embarquement_buses(id) ON DELETE SET NULL,             -- hors-Tibus, référentiel
  route_label text NOT NULL,          -- dénormalisé à l'ouverture (itineraire_id, ou Tibus, ou saisie ad-hoc de secours)
  bus_label text,                     -- dénormalisé à l'ouverture (bus_id, ou Tibus, ou saisie ad-hoc de secours)
  gare_id uuid REFERENCES "Gares"(id) ON DELETE SET NULL,
  capacity_declared integer,          -- requis si hors-Tibus (no-show numérique) — repris de bus_id.capacity si fourni
  opened_by uuid NOT NULL REFERENCES "Users"(id),
  opened_at timestamptz NOT NULL DEFAULT now(),
  closed_at timestamptz,
  CHECK (closed_at IS NULL OR closed_at >= opened_at)
);
CREATE INDEX embarquement_sessions_company_idx ON embarquement_sessions(company_id, opened_at DESC);

CREATE TABLE embarquement_scans (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id uuid NOT NULL REFERENCES embarquement_sessions(id) ON DELETE CASCADE,
  scanned_at timestamptz NOT NULL DEFAULT now(),
  scanned_by uuid NOT NULL REFERENCES "Users"(id),
  raw_payload text NOT NULL,          -- contenu brut du QR, toujours conservé
  source text NOT NULL CHECK (source IN ('tibus', 'external', 'manual')),
  tibus_result text,                  -- résultat brut de verify_ticket_qr si source='tibus'
  matched_reservation_bus_id uuid REFERENCES "ReservationBus"(id) ON DELETE SET NULL,
  passenger_name text,
  ticket_number text,
  origin_label text,
  destination_label text,
  status text NOT NULL CHECK (status IN ('valid', 'duplicate', 'wrong_session', 'invalid'))
);
CREATE INDEX embarquement_scans_session_idx ON embarquement_scans(session_id, scanned_at DESC);
CREATE UNIQUE INDEX embarquement_scans_unique_ticket_per_session
  ON embarquement_scans(session_id, ticket_number)
  WHERE ticket_number IS NOT NULL AND status = 'valid';

-- V2 : liste nominative attendue pour une session hors-Tibus (no-show nominatif
-- même sans réservation Tibus).
CREATE TABLE embarquement_expected_passengers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id uuid NOT NULL REFERENCES embarquement_sessions(id) ON DELETE CASCADE,
  passenger_name text NOT NULL,
  ticket_number text
);
```

Fonctions serveur nécessaires (pattern `SECURITY DEFINER` + garde de rôle,
identique à `_assert_bordereau_access` / `_assert_lot_access` déjà en place) :

- `_assert_embarquement_access(p_company_id)` — même liste de rôles que
  `SCANNER_ROLES` côté web : `owner`, `controleur`, `vendeur`, `chauffeur`,
  `super_admin`. Aucune vérification de module B (décision utilisateur, §2).
- `list_embarquement_itineraires(p_company_id)` / `admin_upsert_embarquement_itineraire(...)` /
  `admin_delete_embarquement_itineraire(p_id)` — lecture pour tout rôle
  Embarquement, écriture réservée à `owner`/`super_admin` (pattern
  `_assert_embarquement_admin_access`, identique à l'idée `has_embarquement_admin_role`
  déjà présente dans le `files.zip` fourni, reprise ici scopée à `kqudaqtydimjclwaihqr`).
- `list_embarquement_buses(p_company_id)` / `admin_upsert_embarquement_bus(...)` /
  `admin_delete_embarquement_bus(p_id)` — même pattern lecture/écriture.
- `list_embarquement_departures(p_company_id)` — **nouvelle RPC fine**, pas de
  portage de `listOwnerDeparturesSupabase()` en Dart : reprend la même requête
  SQL (Reservations + ProgrammationTrajets + Gares + Bus) mais renvoie
  directement `totalSeats/seatsAvailable/seatsBooked/origin/destination/bus`
  en JSON, pour un départ Tibus donné — alimente l'écran « choisir un départ
  existant » à l'ouverture de session.
- `open_embarquement_session(p_company_id, p_reservation_id, p_itineraire_id, p_bus_id, p_route_label, p_bus_label, p_capacity_declared, p_gare_id)`
  — `p_reservation_id` pour un départ Tibus existant ; `p_itineraire_id`/`p_bus_id`
  pour un départ hors-Tibus référencé (auto-remplit `route_label`/`bus_label`/
  `capacity_declared` depuis le référentiel) ; `p_route_label`/`p_bus_label`
  restent acceptés en saisie libre de secours si l'itinéraire/bus n'est pas
  encore dans le référentiel.
- `embarquement_scan_tibus(p_session_id, p_raw_payload, p_reference, p_token)` —
  appelle `verify_ticket_qr` en interne, journalise le résultat.
- `embarquement_scan_external(p_session_id, p_raw_payload, p_passenger_name, p_ticket_number, p_origin_label, p_destination_label)`
  — enregistre tel quel les champs déjà extraits/corrigés côté client, détecte
  les doublons dans la session.
- `list_embarquement_manifest(p_session_id)`
- `close_embarquement_session(p_session_id)`
- `embarquement_report(p_session_id)` — total scanné, valides, doublons, places
  disponibles, no-show (nominatif pour Tibus via `boardedAt IS NULL` sur les
  billets payés du départ ; numérique pour hors-Tibus via `capacity_declared −
  scannés valides`), calculable uniquement après `closed_at`.

## 5. Le parseur QR externe (inchangé par rapport au plan initial, confirmé pertinent)

Cascade, jamais d'échec silencieux :

1. **JSON** — alias multiples par champ (nom, ticket, départ, destination).
2. **URL avec query params** — mêmes alias.
3. **Texte délimité** — heuristique `;`, `|`, ou `clé: valeur` par ligne.
4. **Repli** — payload brut conservé, champs vides, écran de correction manuelle.

Chaque scan externe passe **systématiquement** par un écran de correction avant
validation, jamais d'ajout silencieux au manifeste.

## 6. Structure du projet Flutter (calée sur l'arborescence réelle de `courrier_mobile`)

```
embarquement/
  lib/
    core/
      config/        # env.dart (même URL/clé Supabase kqudaqtydimjclwaihqr, cf. courrier_mobile/lib/core/config/env.dart)
      router/
      theme/
      utils/
      widgets/
    data/
      models/
        embarquement_session.dart
        embarquement_scan.dart
        manifest_row.dart
      services/
        embarquement_service.dart   # wrap des RPC + parseur QR externe
        ticket_qr_parser.dart       # portage de parseTicketQrPayload()
    features/
      auth/                        # login_screen.dart, portage direct de courrier_mobile/lib/features/auth/
      referentiel/
        itineraires_screen.dart     # CRUD itinéraires hors-Tibus (owner/super_admin)
        buses_screen.dart           # CRUD bus hors-Tibus (owner/super_admin)
      session/
        open_session_screen.dart   # choix départ Tibus existant OU itinéraire+bus du référentiel OU saisie libre de secours
      scan/
        scan_screen.dart            # caméra QR (mobile_scanner, déjà en dépendance courrier_mobile), 4 couleurs
        external_scan_review_sheet.dart
      manifest/
        manifest_screen.dart
      report/
        report_screen.dart
        report_export.dart          # PDF (package pdf/printing, déjà utilisés côté courrier_mobile)
  branding/                         # copié de courrier_mobile/branding/ si multi-marque nécessaire dès la V1, sinon reporté
  tool/
    hostinger_migration/            # gabarit repris tel quel pour anticiper une migration compagnie par compagnie
  pubspec.yaml                      # mêmes dépendances clés que courrier_mobile : supabase_flutter, flutter_riverpod,
                                     # go_router, mobile_scanner, qr_flutter, pdf, printing, barcode
```

Connexion Supabase : même projet `kqudaqtydimjclwaihqr`, mêmes comptes/rôles
que Tibus (`owner`, `controleur`, `vendeur`, `chauffeur`, `super_admin`) — un
utilisateur qui a déjà un compte Tibus se connecte avec les mêmes identifiants,
pas de nouveau système d'auth à construire.

## 7. Écrans (repris du plan initial, deux ajustements)

**Référentiel** (owner/super_admin uniquement) : deux écrans CRUD simples —
itinéraires (origine/destination) et bus (libellé/capacité) — accessibles
depuis un menu réglages, pré-requis pour ouvrir une session hors-Tibus
référencée (voir §8.3).

**Ouverture de session** : trois chemins — départ Tibus existant
(`list_embarquement_departures`), itinéraire+bus du référentiel hors-Tibus, ou
saisie libre de secours (route/bus en texte) si rien n'est encore déclaré.

**Scan** : 4 états couleur — vert (valide), orange (doublon Tibus OU doublon
externe dans la session), rouge (déjà à bord / refusé / compagnie invalide),
bleu/gris neutre (QR externe reconnu, en attente de correction manuelle avant
validation). Pour un scan Tibus, seule la référence est lue sur le QR ; nom,
gare de départ/destination et date affichés sur le manifeste viennent de la
réponse `verify_ticket_qr()` (voir §3), pas du contenu du QR.

**Rapport** : trois chiffres — total embarqués, places disponibles, no-show —
avec détail nominatif quand disponible (Tibus, ou externe si liste attendue
chargée), bouton clôturer qui fige le calcul.

## 8. Points tranchés (décisions utilisateur, plus rien en attente avant la Phase 0)

1. **Une étape ou deux ?** (§3) — **tranché : une seule étape**, scan = embarqué
   direct (`p_record_boarding=true`), jamais d'appel à `confirm_passenger_on_board`.
2. **Gate module B** — **tranché : non**, Embarquement est un module
   indépendant, pas de dépendance au module B du scanner web.
3. **Départs hors-Tibus récurrents** — **tranché : référentiel dès la V1**
   (§4), pas de simple saisie libre à chaque session. `embarquement_itineraires`
   et `embarquement_buses`, propres à Embarquement, sans dupliquer
   `Gares`/`Bus`/`ProgrammationTrajets` de Tibus 1.0 — un transporteur sans
   billetterie Tibus déclare ses itinéraires/bus une fois (écrans
   `referentiel/`, §6-§7), puis les réutilise à chaque ouverture de session.
   La saisie libre (`route_label`/`bus_label` texte) reste un repli disponible
   à l'ouverture de session si l'itinéraire/bus n'est pas encore déclaré.

## 9. Phasage

| Phase | Contenu | Sortie |
|---|---|---|
| **0 — Fondations** | Schéma SQL (§4, y compris `embarquement_itineraires`/`embarquement_buses`) + RPC, squelette Flutter (§6), auth réutilisant les comptes Tibus existants, écrans `referentiel/` (CRUD itinéraires/bus, owner/super_admin) | Projet qui compile, connexion + liste de sessions vide + référentiel hors-Tibus utilisable |
| **1 — Scan Tibus** | Ouverture de session sur un départ Tibus existant (`list_embarquement_departures`), scan + couleurs, écriture dans `embarquement_scans` via `embarquement_scan_tibus` | Session Tibus scannable de bout en bout |
| **2 — Scan externe** | Parseur multi-format + écran de correction, `embarquement_scan_external` | QR tiers exploitable |
| **3 — Manifeste** | Liste temps réel, recherche, ajout manuel de secours | Manifeste consultable pendant la session |
| **4 — Rapport & clôture** | `embarquement_report`, no-show nominatif + numérique, export PDF/CSV | Rapport livrable en fin de session |
| **5 — Durcissement** | Permissions fines, mode hors-ligne (queue de scans à synchroniser), tests sur gros manifeste | Prêt terrain |

## 10. Risques

- **Formats QR tiers imprévisibles** — correction manuelle systématique, pas
  une option de repli occasionnelle.
- **Doublons inter-sources** — un billet Tibus scanné en `source='tibus'` puis
  re-scanné en `manual` doit être détecté : croiser `matched_reservation_bus_id`
  ET `ticket_number` selon la source.
- **No-show hors-Tibus sans liste nominative (V1)** — chiffre fiable (attendu
  − scannés) mais sans les noms ; à annoncer clairement dans l'écran rapport.
- **Ambiguïté boardedAt/onBoardAt** (§3) non tranchée avant la Phase 1 risque
  de faire refaire l'écran Scan une fois la V1 codée.
