#!/usr/bin/env bash
# Importe les CSV produits par 03_export_sis_data.sh dans l'instance
# Supabase self-hosted (Hostinger), APRÈS y avoir rejoué dans l'ordre :
#   1. 02_table_schema_pg_dump.sh  (structure des tables)
#   2. 01_generate_functions_and_triggers.sql (fonctions + triggers)
#   3. 03_export_sis_data.sh -> ce script (les données)
#
# session_replication_role = replica désactive TOUS les triggers ET la
# vérification des contraintes FK pour la session : nécessaire ici pour
# deux raisons précises :
#   - les triggers de seed (tg_seed_company_colis_natures /
#     tg_seed_company_expense_categories, déclenchés à l'INSERT dans
#     "Companies") généreraient leurs propres lignes dans colis_natures /
#     CompanyExpenseCategory, qui entreraient en conflit (contrainte
#     unique) avec les lignes réellement exportées de Tibus 1.0 juste
#     après ;
#   - l'ordre d'import ci-dessous respecte déjà les dépendances FK, mais
#     replica évite d'avoir à s'en soucier si l'ordre changeait.
#
# Usage :
#   HOSTINGER_DB_URL="postgresql://postgres:MOTDEPASSE@<ip-ou-domaine>:5432/postgres" \
#     ./04_import_data.sh
set -euo pipefail

if [ -z "${HOSTINGER_DB_URL:-}" ]; then
  echo "Renseigner HOSTINGER_DB_URL (connection string de l'instance Supabase self-hosted sur Hostinger)." >&2
  exit 1
fi

IN_DIR="sis_export"
if [ ! -d "$IN_DIR" ]; then
  echo "Dossier $IN_DIR introuvable : lancer 03_export_sis_data.sh d'abord." >&2
  exit 1
fi

load() {
  local table="$1" file="$2"
  echo "==> $table"
  psql "$HOSTINGER_DB_URL" -c "\copy $table FROM '$IN_DIR/$file' WITH CSV HEADER"
}

psql "$HOSTINGER_DB_URL" -c "SET session_replication_role = replica;" >/dev/null

# Ordre : tables de référence -> Companies -> tout le reste. Avec
# session_replication_role = replica les FK ne sont de toute façon pas
# vérifiées pendant le chargement, mais un ordre logique reste plus lisible
# en cas d'erreur à corriger manuellement.
load '"Countries"'                     "Countries.csv"
load '"Role"'                          "Role.csv"
load '"ContactSettings"'               "ContactSettings.csv"
load '"Companies"'                     "Companies.csv"
load '"CompanyFeatureModules"'         "CompanyFeatureModules.csv"
load '"CompanyExpenseCategory"'        "CompanyExpenseCategory.csv"
load '"Users"'                         "Users.csv"
load '"UserRoles"'                     "UserRoles.csv"
load '"Gares"'                         "Gares.csv"
load '"Bus"'                           "Bus.csv"
load 'caisses_gares'                   "caisses_gares.csv"
load 'colis_natures'                   "colis_natures.csv"
load 'colis_autonomes'                 "colis_autonomes.csv"
load 'colis_natures_selectionnees'     "colis_natures_selectionnees.csv"
load 'colis_numerotation_gares'        "colis_numerotation_gares.csv"
load '"Notifications"'                 "Notifications.csv"
load '"DeviceTokens"'                  "DeviceTokens.csv"
load '"ColisTrackingSubscriptions"'    "ColisTrackingSubscriptions.csv"

psql "$HOSTINGER_DB_URL" -c "SET session_replication_role = DEFAULT;" >/dev/null

echo
echo "Import terminé."
echo
echo "Vérifications recommandées avant de couper Tibus 1.0 pour SIS :"
echo "  - Comparer les comptages : SELECT count(*) FROM colis_autonomes; (idem"
echo "    sur les deux bases, doit correspondre au nombre de lignes exportées)."
echo "  - Tester une connexion agent (login) -- nécessite d'avoir migré"
echo "    auth.users séparément, voir README.md."
echo "  - Tester un enregistrement de colis de bout en bout sur l'instance"
echo "    Hostinger avant bascule définitive du client mobile (brand.json)."
echo "  - Re-uploader les photos du bucket \"colis-photos\" (non couvert ici,"
echo "    voir README.md)."
