# Tibus — Scripts Supabase (ordre d'exécution DEFINITIF)

> Projet : `kqudaqtydimjclwaihqr`

## Ordre strict

| Étape | Fichier | Statut |
|-------|---------|--------|
| 1 | `init_schema.sql` | ✅ Déjà exécuté |
| 2 | `001_roles_model.sql` | ✅ Exécuté |
| 3 | `002_rls_policies.sql` | ✅ Exécuté |
| 4 | `003_seed_countries.sql` | ✅ Exécuté |
| 5 | `005_grant_super_admin_tabiscompany.sql` | ✅ Exécuté |
| 6 | `006_profile_completion.sql` | ✅ Exécuté |
| 7 | `007_seed_demo_data.sql` | ✅ Exécuté |
| 8 | `008_payment_insert_rls.sql` | ⏳ **À exécuter** — réservation voyageur |
| 9 | `009_cancel_booking_rls.sql` | ⏸ **Reporter** — inutile tant qu'aucun ticket non payé n'est créé |
| 10 | `010_seed_live_test_trip_200.sql` | ⏳ **Test paiement live** — trajet Abidjan→Yamoussoukro à **200 XOF** |
| 11 | `011_reservationbus_passenger_seat.sql` | ⏳ **À exécuter** — nom passager + verrouillage siège payé |
| 12 | `012_occupied_seats_rpc.sql` | ⏳ **À exécuter** — lecture publique sécurisée des sièges occupés |
| 13 | `013_seller_counter_sale_rpc.sql` | ⏳ **À exécuter** — vente guichet vendeur Supabase |
| 14 | `014_sales_channels_and_seller_reservations.sql` | ⏳ **À exécuter** — canaux vente/réservation + règle 1 billet voyageur |
| 15 | `015_merchant_agent_applications.sql` | ⏳ **À exécuter** — demandes Agent Marchand + lien Google Maps |
| 16 | `016_accounting_kpis_commissions.sql` | ⏳ **À exécuter** — caisse/comptabilité/KPI compagnie + commissions vendeurs hors compagnie |
| 17 | `017_owner_operations_rpc.sql` | ⏳ **À exécuter** — opérations owner Supabase (création itinéraires + assignation vendeurs) |
| 18 | `018_commission_settings_admin.sql` | ⏳ **À exécuter** — configuration commissions par pays/compagnie + panneau admin Supabase |
| 19 | `019_gateway_payment_fees.sql` | ⏳ **À exécuter** — frais gateway Y/Z/F par pays/méthode + calcul voyageur |
| 20 | `020_traveler_payment_total_rpc.sql` | ⏳ **À exécuter** — RPC calcul montant voyageur T (après 018 + 019) |
| 21 | `021_gateway_payment_fee_resolve_fix.sql` | ⏳ **À exécuter** — fallback méthode + erreurs détaillées |
| 22 | `022_gateway_payment_network.sql` | ⏳ **À exécuter** — Y par réseau (orange/mtn/moov/wave) + fallback Y max |
| 23 | `023_traveler_payment_notice.sql` | ⏳ **À exécuter** — message popup paiement voyageur (super_admin) |
| 24 | `024_gateway_fees_nullable.sql` | ⏳ **À exécuter** — Z/F nullable + correctif lot 22 + sauvegarde admin |
| 92 | `supabase/migrations/092_company_expenses_ohada.sql` | ✅ **Exécuté** — dépenses compagnie + compte de résultat SYSCOHADA |
| 93 | `supabase/migrations/093_chauffeur_role_gares_cities.sql` | ✅ **Exécuté** — rôle chauffeur + gares liées aux villes |
| 94 | `supabase/migrations/094_expense_categories_all_companies.sql` | ✅ **Exécuté** — 11 types de dépenses preset pour toutes les compagnies |
| 95 | `supabase/migrations/095_seed_cities_dr5hn.sql` | ✅ **Exécuté** — ~2180 villes (23 pays Tibus, source dr5hn) |
| 96 | `supabase/migrations/096_geniuspay_traveler_fee_formula.sql` | ✅ **Exécuté** — GeniusPay : T = (M×(1+X)+F)/(1-Z), sans Y opérateur |
| 97 | `supabase/migrations/097_geniuspay_additive_fee_formula.sql` | ✅ **Exécuté** — GeniusPay : MT = M×(1+X+Y)+F |
| 98 | `supabase/migrations/098_geniuspay_full_additive_formula.sql` | ✅ **Exécuté** — GeniusPay : MT = M×(1+X+Y+Z)+F |
| 99 | `supabase/migrations/099_geniuspay_platform_margin_only.sql` | ✅ **Exécuté** — GeniusPay API = M×(1+X) seulement |
| 100 | `supabase/migrations/100_geniuspay_gross_nominal_deducted.sql` | ✅ **Exécuté** — GeniusPay API = M×(1+X+Y+Z)+F, déduction Y%×M + Z%×M + F |
| 101 | `supabase/migrations/101_geniuspay_deducted_on_gross.sql` | ✅ **Exécuté** — GeniusPay : T=(V+F)/(1-Y-Z), frais sur T |
| 102 | `supabase/migrations/102_orange_ci_geniuspay_5pct.sql` | ✅ **Exécuté** — Orange CI Y=5% (Paystack) |

## Politique anti-fraude (réservation voyageur)

- **Aucun ticket** (`TB-…`) ni ligne `ReservationBus` avant **paiement confirmé**
- **Aucun blocage de siège** avant paiement — seuls les billets payés comptent dans la capacité
- Les sièges payés sont enregistrés dans `ReservationBus.seatNumber` et ne sont plus proposés à la vente
- **Pas de reçu** accessible pour les parcours non payés (`/booking/:id` bloqué)
- Brouillon local (sessionStorage) pour « continuer plus tard » sur le même appareil
- Popup si le siège n'est plus disponible au moment de valider

## Paiement FedaPay (Edge Functions)

| Function | Rôle |
|----------|------|
| `fedapay-initialize` | Crée transaction FedaPay + URL checkout (vérifie places) |
| `fedapay-verify` | Après retour utilisateur → émet ticket `TB-…` en base |
| `fedapay-webhook` | Secours si l'utilisateur ferme l'onglet avant verify |

### Secrets Supabase (Dashboard → Edge Functions → Secrets)

```
FEDAPAY_SECRET_KEY=sk_live_... ou sk_sandbox_...
FEDAPAY_BASE_URL=https://sandbox-api.fedapay.com   # ou https://api.fedapay.com
SUPABASE_SERVICE_ROLE_KEY=...   # auto-injecté au deploy
```

### Déploiement

```bash
cd /Users/tabistabis.tg/Documents/tibus-front
supabase link --project-ref kqudaqtydimjclwaihqr
supabase secrets set FEDAPAY_SECRET_KEY=sk_...
supabase secrets set FEDAPAY_BASE_URL=https://sandbox-api.fedapay.com
supabase functions deploy fedapay-initialize
supabase functions deploy fedapay-verify
supabase functions deploy fedapay-webhook
```

### Webhook FedaPay

URL : `https://kqudaqtydimjclwaihqr.supabase.co/functions/v1/fedapay-webhook`

### Parcours

1. TripDetail → Payer maintenant → FedaPay checkout
2. Retour → `/payment/verify?reservationId=…&id=…` → ticket émis
3. Reçu accessible uniquement après succès verify

## Données de démo (`007_seed_demo_data.sql`)

Crée **Tibus Démo Transport** (Côte d'Ivoire) :

| Élément | Détail |
|---------|--------|
| Villes | Abidjan, Yamoussoukro, Bouaké |
| Gares | Adjamé, Yamoussoukro, Bouaké |
| Trajets | Abidjan → Yamoussoukro (5 000 XOF), Abidjan → Bouaké (3 500 XOF) |
| Bus | 1 Mercedes Sprinter, 45 places |
| Départs | 14 jours à venir, 6h et 14h (UTC) |
| Owner | `tabiscompany@gmail.com` → rôle `owner` sur la compagnie |

Script **idempotent** : supprime et recrée la compagnie démo à chaque exécution.

## Auth frontend (migration)

| Variable | Valeur |
|----------|--------|
| `VITE_AUTH_PROVIDER` | `supabase` (nouveau) ou `hercules` (ancien) |

**Supabase Dashboard → Authentication :**
- Email provider : activé
- Site URL : `http://localhost:5173`
- Redirect URLs : `http://localhost:5173/auth/callback`

## Hiérarchie des rôles (version corrigée)

### A. Plateforme (`companyId` = NULL)

```
super_admin
  └── admin_pays                    (requiert countryId)
  └── master                        (gère son RÉSEAU, commission sur réseau)
        └── vendeur_master            (chef d'équipe réseau)
              └── vendeur_reseau      (assigné par master, PAS auto-inscription)
  └── master_independant            (vente toutes compagnies)

vendeur_independant                 ← AUTO-INSCRIPTION, plateforme directe
                                      HORS réseau master, commission sans master

traveler                            ← AUTO-INSCRIPTION (défaut)
```

### B. Compagnie (`companyId` requis)

```
owner
  ├── comptable_compagnie
  ├── controleur
  └── vendeur
```

## Deux circuits de vente DISTINCTS

| Circuit | Rôle | Inscription | Commission |
|---------|------|-------------|------------|
| **Indépendant** | `vendeur_independant` | Seul, via plateforme | Directe plateforme (pas de master) |
| **Réseau master** | `vendeur_reseau` | Assigné par `master` / `vendeur_master` | Master touche commission réseau |
| **Compagnie** | `vendeur` | Assigné par `owner` | Employé compagnie |

## Tables clés

| Table | Usage |
|-------|-------|
| `IndependentSellerCompanies` | Compagnies où un **vendeur_independant** peut vendre |
| `MasterVendorNetwork` | Lien master ↔ **vendeur_reseau** (jamais les indépendants) |
| `RoleAssignmentRules` | Qui peut assigner quel rôle |

## Règles importantes

- `vendeur_independant` **n'apparaît pas** dans `RoleAssignmentRules` → auto-inscription
- `master` **ne peut pas** assigner `vendeur_independant`
- `vendeur_master` **ne peut pas** assigner `vendeur_independant`
- Un utilisateur dans `MasterVendorNetwork` **ne peut pas** devenir `vendeur_independant`

## Lot 16 — caisse / comptabilité / commissions

`016_accounting_kpis_commissions.sql` ajoute :

- `get_company_accounting_dashboard(companyId?)` : agrégats RLS-safe pour dashboard compagnie (KPI, revenus caisse, revenus online, commissions vendeurs en attente, courbe 30 jours, dernières ventes).
- `get_seller_commission_summary()` : visibilité vendeur/master sur les commissions de ventes tiers `saleChannel = seller_reservation`.
- Colonnes commission sur `ReservationBus` (`sellerCommissionAmount`, `sellerCommissionStatus`, `sellerCommissionPaidAt`, `commissionCalculatedAt`) + trigger de calcul/backfill.

Hypothèse conservatrice : tant qu'aucun taux dédié vendeur/master n'existe, les commissions hors compagnie utilisent `Companies.commissionRate`. Les ventes guichet internes (`saleChannel = counter_sale`) ne génèrent pas de commission vendeur hors compagnie.

## Lot 17 — opérations owner Supabase

`017_owner_operations_rpc.sql` ajoute des RPC `SECURITY DEFINER` ciblées :

- `create_owner_route(...)` : crée un `ProgrammationTrajets` + son `ProgrammationTrajetArrets` après vérification que les deux gares appartiennent à la compagnie de l'owner courant.
- `find_assignable_company_user_by_email(email)` : recherche RLS-safe d'un utilisateur inscrit par email pour l'ajout vendeur.
- `assign_company_user_role_by_email(email, role)` : assigne un utilisateur existant à la compagnie en rôle `vendeur` ou `controleur`.

Le client ne crée pas d'utilisateur Auth depuis l'espace owner ; si l'email n'existe pas dans `Users`, l'UI affiche qu'aucun utilisateur inscrit n'a été trouvé.

## Lot 18 — configuration commissions Supabase

`018_commission_settings_admin.sql` ajoute :

- `CommissionSettings` : taux par pays, avec override optionnel par compagnie.
- RPC admin `list_commission_settings`, `upsert_commission_setting`, `delete_commission_setting`.
- Résolution RLS-safe : `super_admin` gère tous les pays ; `admin_pays` gère uniquement son `countryId`.
- Trigger `ReservationBus` remplacé : nouvelles ventes tiers utilisent override compagnie → taux pays → fallback legacy `Companies.commissionRate`.
- `get_company_accounting_dashboard` retourne aussi le taux/portée de commission résolu pour l'affichage owner.

`Companies.commissionRate` reste conservé comme fallback legacy tant qu'aucun taux pays/compagnie n'est configuré.

## Fichiers obsolètes

- `001b_schema_roles_evolution.sql` — supprimé


## Lot 19 — frais gateway / GeniusPay

`019_gateway_payment_fees.sql` ajoute :

- `GatewayPaymentFees` : taux Y (gateway), Z (GeniusPay), F (fixe) par `gateway + countryId + method`.
- RPC `resolve_gateway_payment_fee`, `list_gateway_payment_fees`, `upsert_gateway_payment_fee`, `delete_gateway_payment_fee`.
- Droits identiques aux commissions : `super_admin` tous pays, `admin_pays` son pays.
- Le calcul frontend lit ces valeurs + `CommissionSettings` (X) au lieu de taux codés en dur.


## Lot 20 — calcul montant voyageur

`020_traveler_payment_total_rpc.sql` expose `calculate_traveler_payment_total(...)` utilisé par le frontend et `fedapay-initialize`.


## Lot 22 — frais par réseau mobile money

`022_gateway_payment_network.sql` ajoute la colonne `network` sur `GatewayPaymentFees`. Configurez une ligne par réseau FedaPay CI. Si le voyageur choisit « Je ne sais pas », le RPC prend le **Y le plus élevé**.

## Lot 23 — popup voyageur

`023_traveler_payment_notice.sql` : texte éditable admin pour le popup de paiement voyageur.

## Lot 24 — frais gateway nullable

`024_gateway_fees_nullable.sql` : Z/F optionnels + correctifs réseau.

## Lot 25 — modèle FedaPay on_top

`025_fedapay_fee_on_top.sql` : l'API FedaPay reçoit V (net plateforme), le voyageur paie T ≈ V × (1 + Y) + F.

## Lot 26 — annulation + pénalités + journal ventes

| Fichier | Statut |
|---------|--------|
| `026_cancellation_penalties.sql` | ⏳ **À exécuter** |
| `026b_accounting_exclude_cancelled.sql` | ⏳ **À exécuter après 026** |

Ajouts :
- Colonnes `ReservationBus` : `ticketStatus`, `cancelledAt`, `penaltyAmount`, `refundAmount`, etc.
- Tables `CompanyCancellationPolicy` + `CompanyCancellationPenaltyTier` (période → tx % ou fixe).
- Délai critique : sous le seuil, annulation **owner/vendeur** uniquement avec pénalité critique.
- Remboursement = **M − P** (M = montant encaissé, P = pénalité).
- RPC : `get/upsert_company_cancellation_policy`, `list_company_ticket_sales`, `preview_ticket_cancellation`, `cancel_company_ticket`.
- Visibilité ventes : `owner`, `comptable_compagnie`, `controleur`, `vendeur`.
- Annulation : `owner`, `vendeur` (impact caisse).

UI Supabase :
- Owner : `/owner/sales`, `/owner/cancellation-policy`
- Staff compagnie (comptable/controleur) : `/company/sales`
- Vendeur compagnie : onglet « Ventes compagnie » dans `/seller`

## Lot 28 — fond de garantie

`028_guarantee_fund.sql` ajoute :

- `Companies.guaranteeBalance` (Solde)
- `CompanyGuaranteeLedger` : historique Date / Type / Montant / Solde / Auteur / Réf.
- **Dépôt** (`deposit`) : Solde + X — admin `super_admin` ou `admin_pays`
- **Réservation** (`reservation`) : Solde − M — canaux `traveler` et `seller_reservation` uniquement
- **Libération** (`release`) : crédit M à l'annulation
- Blocage si `Solde < M` (code `GUARANTEE_FUND_INSUFFICIENT` côté FedaPay)
- RPC : `deposit_company_guarantee_fund`, `check_company_guarantee_sufficient`, `deduct_company_guarantee_fund`, `get/list_company_guarantee_fund`

**Ne concerne pas** `counter_sale` (guichet compagnie).

Redéployer après SQL : `fedapay-initialize`, `fedapay-verify`, `fedapay-webhook` (partagent `issue-ticket.ts`).

## Lot 29 — solde négatif + validation dépôts

`029_guarantee_negative_deposit_validation.sql` ajoute :

- `Companies.guaranteeAllowNegative` : si activé par l'owner, le solde peut passer sous zéro (réservations non bloquées)
- `CompanyGuaranteeDeposit` : dépôt en attente avec `receiptPath` (relevé obligatoire)
- Workflow : admin soumet dépôt + relevé → owner/comptable valide → Solde + X
- Bucket storage `guarantee-deposit-receipts` (PDF, JPEG, PNG, WebP)
- RPC : `submit_company_guarantee_deposit`, `approve/reject_company_guarantee_deposit`, `upsert_company_guarantee_settings`

## Lot 27 — filtres journal ventes

`027_company_sales_filters.sql` étend `list_company_ticket_sales` avec :
- `p_sale_channel` : voyageur / guichet / réservation tiers
- `p_created_from` / `p_created_to` : période de vente
- `p_departure_from` / `p_departure_to` : date de départ
- `p_search` : nom voyageur ou référence ticket (ILIKE)

## 046 — Gestion utilisateurs / rôles

Exécuter `046_user_role_management.sql` dans le SQL Editor Supabase.

- `assign_company_user_role_by_email` : vendeur, comptable_compagnie, controleur
- `remove_company_user_role(user_id, role)` : retrait d'un rôle compagnie (owner)
- `admin_assign_user_role` / `admin_remove_user_role` : super admin

Edge function à déployer :

```bash
supabase functions deploy admin-provision-user
```

Crée un compte Auth + profil `Users` + rôles (owner limité à sa compagnie ; super admin tous rôles).

## 047 — Liste équipe + caisse session vendeur

Exécuter `047_team_list_and_cash_session.sql`.

- `list_owner_team_members(company_id)` : liste RPC pour l'onglet Équipe owner
- Caisse : une session ouverte par vendeur (tous trajets du jour)
- `seller_counter_sale` : utilise la caisse ouverte du vendeur, plus la gare de départ du trajet
- Comptable : validation reversements uniquement (`/company/cash-register`)

## 048 — Flux caisse vendeur (corrige "Ouverture impossible")

Exécuter `048_cash_session_flow.sql` (après 031, idéalement après 047).

Prérequis vendeur : rôle `vendeur` + `companyId` sur UserRoles + au moins une gare en base.

Flux :
1. `open_station_cash_register` — fond de roulement, session unique par vendeur
2. Ventes via `seller_counter_sale` — créditent la session ouverte
3. `submit_station_cash_reversal` — fin de service, statut `en_reversement`
4. `validate_station_cash_reversal` — comptable ou owner, clôture `cloturee`

## Lot 092 — Dépenses & compte de résultat OHADA

Exécuter `supabase/migrations/092_company_expenses_ohada.sql` dans le SQL Editor Supabase **ou** via CLI :

```bash
cd /Users/tabistabis.tg/Documents/tibus-front
supabase db query --linked -f supabase/migrations/092_company_expenses_ohada.sql
```

| Fichier | Statut |
|---------|--------|
| `supabase/migrations/092_company_expenses_ohada.sql` | ✅ Exécuté (prod `kqudaqtydimjclwaihqr`) |

- Tables `CompanyExpenseCategory`, `CompanyExpense` (imputation membre équipe XOR bus+gare).
- Types prédéfinis : carburant, réparations, pièces, salaires, électricité, communication, internet, matériel bureau, marketing, abonnement TV (+ CRUD).
- RPCs : `list/upsert/delete_company_expense_category`, `list/upsert/delete_company_expense`, `get_company_income_statement` (SYSCOHADA).
- UI owner : `/owner/expenses`, `/owner/income-statement`.

## Lot 094 — Types de dépenses pour toutes les compagnies

Exécuter `supabase/migrations/094_expense_categories_all_companies.sql` :

```bash
supabase db query --linked -f supabase/migrations/094_expense_categories_all_companies.sql
```

| Type | Compte SYSCOHADA | Libellé |
|------|------------------|---------|
| Carburant | 6047 | Achats de carburants et lubrifiants |
| Réparations | 6156 | Entretien, réparations et maintenance |
| Pièces détachées | 6042 | Achats de pièces et fournitures consommables |
| Salaires équipe | 6412 | Salaires, appointements et commissions du personnel |
| Électricité | 6052 | Eau et électricité |
| Communication | 6241 | Frais de téléphone et communication |
| Internet | 6248 | Frais d'Internet |
| Achat de matériel de bureau | 6045 | Achats de matériel et fournitures de bureau |
| Marketing | 6228 | Publicité, publications et relations publiques |
| Abonnement TV | 6288 | Abonnements et services (TV, médias) |
| Transports interne | 6135 | Transports internes et déplacements exploitation |

- Seed automatique pour **toutes les compagnies existantes** (`seed_all_companies_expense_categories`).
- Trigger `companies_seed_expense_categories` : chaque **nouvelle compagnie** reçoit les 11 types à l'inscription.

## Lot 118–119 — Métriques scaling & notifications super_admin

```bash
npm run supabase:push
# ou : supabase db push (projet Tibus kqudaqtydimjclwaihqr uniquement)
```

| Fichier | Contenu |
|---------|---------|
| `118_platform_scaling_superadmin_notifications.sql` | Tables `PlatformScalingState`, `PlatformSuperAdminNotifications`, RPC métriques + sync notifications |
| `119_fix_platform_scaling_metrics.sql` | Correctif `upcomingTrips7d` (colonne `Reservations.date`) |

## Lot 120–121 — Modules commerciaux A–F par compagnie

Voir aussi `docs/COMPANY_FEATURE_MODULES.md`.

```bash
npm run supabase:push
```

| Fichier | Contenu |
|---------|---------|
| `120_company_feature_modules.sql` | Table `CompanyFeatureModules`, RLS, RPC `company_has_module`, `get/set_company_feature_modules`, backfill A–E=true |
| `121_company_feature_module_guards.sql` | Garde RPC/triggers : guichet (A), scan (B), compta (C), colis (D), promo (E) |

**Frontend** : panneau admin sur fiche compagnie (`CompanyFeatureModulesPanel`), filtre console owner + sidebar, garde `/seller` (A) et `/verify/scan` (B).

**Déploiement Vercel** : `npm run build` puis push branche (i18n `feature_modules`, `scaling_metrics`).

## Lot 122 — Rôle démarcheur + dashboard

```bash
npm run supabase:push
```

| Fichier | Contenu |
|---------|---------|
| `122_demarcheur_role_dashboard.sql` | Rôle `demarcheur`, RPC `get_demarcheur_dashboard`, `is_demarcheur()` |

Route UI : `/admin/demarcheur` — performance des compagnies recrutées + commissions stakeholder recruteur.

## Lot 128–131 — Colis autonomes

| Fichier | Contenu |
|---------|---------|
| `128_sync_colis_module_d.sql` | Sync `colis_autonome_enabled` ↔ module commercial D |
| `129_fix_list_colis_autonomes_order.sql` | Fix RPC `list_colis_autonomes` (`ORDER BY sub."createdAt"`) |
| `130_colis_cash_and_sales_journal.sql` | Encaissement caisse (`encaissement_colis`) à l'enregistrement + journal des ventes (`colis_autonome`) |
| `131_module_d_colis_sms_owner_config.sql` | Option admin : owner autorisé à configurer les SMS colis (`moduleDColisSmsConfig`) |
| `132_colis_sms_send_gate.sql` | Envoi SMS colis conditionné à l'option admin + étapes activées par l'owner |
| `133_colis_caisse_journal_print.sql` | Caisse session vendeur, journal canal Guichet (CL-…), encaissement guichet unifié |
| `134_cash_open_pick_gare.sql` | Ouverture caisse vendeur avec gare obligatoire (plus de hub invisible), libellé gare réel |
| `135_mouvements_caisse_colis_autonome_fk.sql` | Encaissement colis autonome via `colis_autonome_id` (FK `colis_autonomes`, plus `ReservationBus`) |
| `136_cash_sale_departure_gare_only.sql` | Vente cash limitée aux départs de la gare de caisse ouverte (`assert_seller_cash_departure_gare`) |
| `137_colis_retrait_qr_reference.sql` | Retrait colis via QR (UUID) ou référence `CL-XXXXXXXX` (`resolve_colis_retrait_code`, `deliver_colis_autonome(text)`) |
| `138_colis_sms_gate_sync.sql` | Sync porte admin SMS colis / flags owner, `build_colis_sms_payload` + `skipReason` |
| `139_colis_sms_message_cl_reference.sql` | SMS colis avec référence `CL-XXXXXXXX` (plus UUID complet) |
| `140_record_station_cash_movement_unique.sql` | ✅ Exécuté — supprime la surcharge `record_station_cash_movement` (fix vente guichet « function is not unique ») |

## SMS colis — Infobip (essai 60 jours)

Provider sélectionné par `SMS_PROVIDER=infobip` ou présence de `INFOBIP_API_KEY`.

```bash
./scripts/supabase-project-check.sh

supabase secrets set \
  SMS_PROVIDER=infobip \
  INFOBIP_API_KEY="votre_cle_api" \
  INFOBIP_SENDER="ServiceSMS" \
  INFOBIP_BASE_URL="https://VOTRE_SUBDOMAIN.api.infobip.com"

supabase functions deploy colis-sms-notify --no-verify-jwt
```

| Secret | Où le trouver (portail Infobip) |
|--------|--------------------------------|
| `INFOBIP_API_KEY` | Developers → API keys → clé avec scope `sms:message:send` |
| `INFOBIP_BASE_URL` | Developers → API base URL (souvent `https://xxxxx.api.infobip.com`) |
| `INFOBIP_SENDER` | Essai gratuit : **`ServiceSMS`** (sender test Infobip) |

**Limites essai gratuit :** envoi uniquement vers le **numéro vérifié** sur le compte Infobip ; crédit limité 60 jours.

Test curl :

```bash
curl -s -X POST "https://VOTRE_SUBDOMAIN.api.infobip.com/sms/3/messages" \
  -H "Authorization: App VOTRE_CLE" \
  -H "Content-Type: application/json" \
  -d '{"messages":[{"sender":"ServiceSMS","destinations":[{"to":"225712960000"}],"content":{"text":"Test Tibus colis"}}]}'
```

Réponse OK : `messages[0].messageId` + statut `PENDING_ACCEPTED`.

## Mise en production — nettoyage données de test

Scripts manuels (ne pas `db push`) :

| Fichier | Rôle |
|---------|------|
| `scripts/prod-cleanup-test-data.sql` | Audit + modèle commenté |
| `scripts/prod-cleanup-execute.sql` | **Prêt à exécuter** — purge **toutes** les compagnies + ventes (utilisateurs conservés) |
| `scripts/run-prod-cleanup.sh` | Lance via `psql` si `SUPABASE_DB_PASSWORD` est défini |

### Compagnies sur prod (audit 19/06/2026)

**Toutes supprimées** par `prod-cleanup-execute.sql` (8 au total), dont :

| Nom | UUID |
|-----|------|
| EDF | `347e11f2-039b-4617-b76b-e29dfef1c5b7` |
| severin travel | `2df2d454-f0fb-4a61-a414-4a37732889ae` |
| Tibus Démo Transport | `5b181dca-ec1d-4990-9346-dbb99f458727` |
| Tabis Express / BF, Test compagnie et frère, Tibus, Tibus ETVT | voir audit |

Suppression en cascade : billets (`ReservationBus`), paiements, caisses, colis, bus, gares, voyages. **Comptes `Users` / `auth.users` conservés** — les lignes `UserRoles` liées aux compagnies purgées sont supprimées (rôles owner/vendeur exigent un `companyId` non null).

### Exécution

**Option A — SQL Editor** (recommandé)  
1. Backup Dashboard → Database → Backups  
2. Coller le contenu de `scripts/prod-cleanup-execute.sql`  
3. Exécuter  

**Option B — Terminal**
```bash
export SUPABASE_DB_PASSWORD='…'   # Dashboard → Database password
./scripts/run-prod-cleanup.sh dry-run   # simulation (ROLLBACK)
./scripts/run-prod-cleanup.sh           # purge réelle
```

Après exécution : table `Companies` vide ; les comptes utilisateurs restent connectables (rôles pays / voyageur inchangés).

## Lot 145 — Rôles gare, itinéraires programmation, commissions guichet

Fichier : **`supabase/migrations/145_gare_roles_itinerary_counter_commission.sql`** — statut : **déployé**

- `UserRoles.gareId` + validation trigger (rôles gare : `gareId` obligatoire).
- Rôles : `gerant_gare`, `vendeur_gare`, `controleur_gare`, `comptable_gare` (+ alias `gestionnaire_gare`).
- `ProgrammationTrajets.isSchedulingActive` — masqué à la programmation des départs si `false` ; reste dans les filtres reporting historique.
- Table `GareCounterCommissionTiers` + RPC `compute_counter_seller_commission`, CRUD tranches, équipe gare (`list/assign/remove_gare_team_*`), `set_trajet_scheduling_active`, `can_manage_gare`, `resolve_user_managed_gare_id`.
- `current_owner_company_id()` étendu aux rôles staff/gare pour les RPC owner.

## Lot 146 — Gérant de gare obligatoire, reversements comptable/gérant gare

Fichier : **`supabase/migrations/146_gare_gerant_assignment_cash_roles.sql`** — statut : **à déployer**

- RPC `assign_gare_gerant(gare_id, user_id)` : owner désigne le gérant avec `UserRoles.gareId` + `Gares.gestionnaireUserId`.
- RPC `resolve_user_gare_id` : résolution gare pour tous rôles gare-scoped.
- `can_validate_station_reversal` / `validate_station_cash_reversal` : `comptable_gare` et `gerant_gare` peuvent valider les reversements de leur gare.
- Front : gérant retiré de l'écran Équipe ; assignation via Gares ; dashboard « Ma gare » pour comptable et gérant.

## Lot 147 — Fusion gestionnaire_gare → gerant_gare

Fichier : **`supabase/migrations/147_merge_gestionnaire_into_gerant_gare.sql`** — statut : **à déployer**

- Migration des `UserRoles` `gestionnaire_gare` vers `gerant_gare` (+ backfill `gareId` depuis `Gares.gestionnaireUserId` / compagnie, purge orphelins).
- Suppression du rôle legacy `gestionnaire_gare` ; fonctions RPC/RLS unifiées sur `gerant_gare`.
- Front : accès dashboards gare (accueil, nav, seller `vendeur_gare`), équipe gérant via `GareTeamPanel`.

## Lot 148 — Caisse guichet vendeur_gare et gares assignées

Fichier : **`supabase/migrations/148_vendeur_gare_station_cash_gares.sql`** — statut : **à déployer**

- `resolve_seller_company_id` / `can_operate_station_cash` : incluent `vendeur_gare`.
- RPC `list_company_station_gares` : vendeur_gare ne voit que sa/ses gare(s) ; vendeur/chauffeur compagnie voient toutes les gares.
- `open_station_cash_register` : contrôle gare assignée pour vendeur_gare.
- Front : ouverture caisse pour `vendeur_gare` ; blocs accueil séparés gérant / comptable / contrôleur / guichet.

## Lot 149 — Vente guichet vendeur_gare

Fichier : **`supabase/migrations/149_vendeur_gare_counter_sale.sql`** — statut : **à déployer**

- RPC `can_seller_counter_sale` : owner, vendeur, chauffeur compagnie **ou** `vendeur_gare` rattaché à une gare.
- `seller_counter_sale` : remplace le contrôle legacy « vendeurs de la compagnie » (bloquait `vendeur_gare` malgré caisse ouverte).
- Front : `getSellerProfileSupabase` résout la compagnie via `gareId` si besoin.

## Lot 150 — Parrainage : fix SELECT FOR UPDATE

Fichier : **`supabase/migrations/150_fix_referral_profile_volatile.sql`** — statut : **à déployer**

- `get_my_referral_profile` : `STABLE` → `VOLATILE` (génère le code parrain via `ensure_user_referral_code`).
- Corrige l’erreur prod « cannot execute SELECT FOR UPDATE in a read-only transaction » sur `/traveler/referral`.

## Compagnie démo + owners (post-purge)

Script manuel : **`scripts/prod-seed-demo-company.sql`**

1. Crée **Tibus Démo Transport** (ou réutilise si déjà présente).
2. Active tous les modules (`CompanyFeatureModules`) et `liveAuthorizedByAdmin` pour les tests internes.
3. **`isActive = false`** et **`arretReservation = false`** → gares et voyages **invisibles** au public (recherche voyageur, carte réseau, filtres compagnies).
4. Attribue le rôle **owner** sur cette compagnie à **chaque ligne** de `Users` (idempotent).

Pour publier plus tard : owner accepte le contrat + active la mise en ligne, ou admin pays passe `isActive` à `true`.

SQL Editor : Ctrl+A sur le fichier → Run. Vérifier que `owner_count = users_total` dans le résultat.
