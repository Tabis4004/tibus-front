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
