# Modules commerciaux compagnie (A–F)

Activation par compagnie des blocs de l'offre commerciale Tibus, alignés sur `docs/offre-commerciale-tibus-modele.docx`.

## Modules

| ID | Intitulé | Prérequis | Garde backend (121) | UI owner |
|----|----------|-----------|---------------------|----------|
| A | Billetterie & exploitation | — | `charge_company_counter_platform_commission` | sales, seller, fleet, trips… |
| B | Scanner & anti-fraude | A | `verify_ticket_qr`, `confirm_passenger_on_board` | `/verify/scan`, cancellation |
| C | Comptabilité analytique | A | `get_company_income_statement`, dépenses | expenses, income-statement, analytics |
| D | Courrier / colis | — | trigger `colis_autonomes` | colis |
| E | Performance (promo, fidélité, API) | A | trigger `PromoCodes` | promo, loyalty, partner-api |
| F | Équipement TPE | — | (flag DB, sur devis) | admin plateforme |

## Migrations SQL (copie de référence)

- `supabase/migrations/120_company_feature_modules.sql` — schéma + RPC lecture/écriture
- `supabase/migrations/121_company_feature_module_guards.sql` — assertions sur RPC sensibles

Appliquer **uniquement** sur le projet Tibus (`kqudaqtydimjclwaihqr`) :

```bash
npm run supabase:check
npm run supabase:push
```

## RPC principales

- `get_company_feature_modules(p_company_id)` → jsonb
- `set_company_feature_modules(p_company_id, p_module_a…f)` → super_admin ou admin_pays du pays
- `company_has_module(p_company_id, 'A'|'B'|…)` → boolean
- `assert_company_module(p_company_id, 'A')` → lève une exception si désactivé

## Frontend

| Fichier | Rôle |
|---------|------|
| `src/lib/company-feature-modules.ts` | Types + `companyModuleEnabled` |
| `src/lib/company-feature-module-map.ts` | Mapping console / routes |
| `src/lib/supabase/company-feature-modules.ts` | Client Supabase |
| `src/hooks/use-company-feature-modules.ts` | Hook chargement |
| `src/hooks/use-owner-company.tsx` | Contexte owner enrichi |
| `src/pages/admin/_components/CompanyFeatureModulesPanel.tsx` | Toggles admin |
| `src/lib/owner-console-modules.tsx` | Filtre tuiles console |

Accès admin : `super_admin` ou `admin_pays` (même pays que la compagnie).

## Lien abonnement (phase 5 — léger)

Les plans d'abonnement owner (`/owner/subscription`) restent indépendants pour l'instant. À terme, un plan pourra pré-cocher des modules via `set_company_feature_modules` à la validation d'abonnement. Le backfill 120 active A–E pour les compagnies existantes (comportement inchangé).

## Déploiement

1. `npm run supabase:push` (Tibus)
2. `npm run build`
3. Déployer sur Vercel (branche principale ou preview)

Sans migration 120, l'UI retombe sur les modules par défaut (tous actifs sauf F).
