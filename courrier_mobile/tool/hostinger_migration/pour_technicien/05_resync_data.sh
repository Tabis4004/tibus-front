#!/usr/bin/env bash
# À utiliser UNIQUEMENT pour une resynchronisation (pas le premier import :
# pour ça, voir 04_import_data.sh). Vide les tables déjà importées puis les
# recharge à neuf depuis les CSV fraîchement reçus -- nécessaire parce que
# les lignes de la première synchro sont déjà en base : rejouer 04 tel quel
# échouerait sur des doublons de clé primaire.
#
# Avant de lancer ce script :
#   1. Remplacer functions_and_triggers.sql, sis_schema_tables.sql et le
#      contenu de sis_export/ par les nouvelles versions reçues.
#   2. Rejouer functions_and_triggers.sql sur l'instance (idempotent --
#      CREATE OR REPLACE FUNCTION, pas besoin de vider quoi que ce soit
#      pour les fonctions/triggers, juste le réexécuter) :
#        psql "$HOSTINGER_DB_URL" -f functions_and_triggers.sql
#   3. Puis lancer CE script pour les données.
#
# Usage :
#   HOSTINGER_DB_URL="postgresql://postgres:MOTDEPASSE@<ip-ou-domaine>:5432/postgres" \
#     ./05_resync_data.sh
set -euo pipefail

if [ -z "${HOSTINGER_DB_URL:-}" ]; then
  echo "Renseigner HOSTINGER_DB_URL." >&2
  exit 1
fi

IN_DIR="sis_export"
if [ ! -d "$IN_DIR" ]; then
  echo "Dossier $IN_DIR introuvable : recopier les nouveaux CSV d'abord." >&2
  exit 1
fi

echo "Cette opération va VIDER puis RECHARGER les tables SIS sur l'instance"
echo "Hostinger. Les données actuellement en base (y compris tout ce qui a"
echo "été enregistré depuis l'instance Hostinger elle-même, si elle est déjà"
echo "en service) seront REMPLACÉES par le contenu des CSV. Ne pas lancer"
echo "après une bascule réelle des agents sur Hostinger, seulement pendant"
echo "la phase de préparation/test."
read -p "Continuer ? (o/N) " confirm
[ "$confirm" = "o" ] || exit 1

load() {
  local table="$1" file="$2"
  echo "==> $table"
  psql "$HOSTINGER_DB_URL" -c "\copy $table FROM '$IN_DIR/$file' WITH CSV HEADER"
}

psql "$HOSTINGER_DB_URL" -c "SET session_replication_role = replica;" >/dev/null

echo "==> Purge des tables"
psql "$HOSTINGER_DB_URL" -c 'TRUNCATE TABLE
  "Countries", "Cities", "Role", "RoleAssignmentRules", "ContactSettings",
  "Companies", "CompanyFeatureModules", "CompanyExpenseCategory", "Users",
  "UserRoles", "Gares", "Bus", caisses_gares, reversements_comptables,
  mouvements_caisse, bordereaux_livraison, bordereau_colis, colis_natures,
  colis_autonomes, colis_natures_selectionnees, colis_numerotation_gares,
  "Notifications", "DeviceTokens", "ColisTrackingSubscriptions";'

load '"Countries"'                     "Countries.csv"
load '"Cities"'                        "Cities.csv"
load '"Role"'                          "Role.csv"
load '"RoleAssignmentRules"'            "RoleAssignmentRules.csv"
load '"ContactSettings"'               "ContactSettings.csv"
load '"Companies"'                     "Companies.csv"
load '"CompanyFeatureModules"'         "CompanyFeatureModules.csv"
load '"CompanyExpenseCategory"'        "CompanyExpenseCategory.csv"
load '"Users"'                         "Users.csv"
load '"UserRoles"'                     "UserRoles.csv"
load '"Gares"'                         "Gares.csv"
load '"Bus"'                           "Bus.csv"
load 'caisses_gares'                   "caisses_gares.csv"
load 'reversements_comptables'         "reversements_comptables.csv"
load 'mouvements_caisse'               "mouvements_caisse.csv"
load 'bordereaux_livraison'            "bordereaux_livraison.csv"
load 'bordereau_colis'                 "bordereau_colis.csv"
load 'colis_natures'                   "colis_natures.csv"
load 'colis_autonomes'                 "colis_autonomes.csv"
load 'colis_natures_selectionnees'     "colis_natures_selectionnees.csv"
load 'colis_numerotation_gares'        "colis_numerotation_gares.csv"
load '"Notifications"'                 "Notifications.csv"
load '"DeviceTokens"'                  "DeviceTokens.csv"
load '"ColisTrackingSubscriptions"'    "ColisTrackingSubscriptions.csv"

psql "$HOSTINGER_DB_URL" -c "SET session_replication_role = DEFAULT;" >/dev/null

echo
echo "Resynchronisation terminée."
echo
echo "Rappel : ceci ne touche PAS auth.users/auth.identities (comptes de"
echo "connexion, déjà migrés séparément) ni le bucket colis-photos -- ces"
echo "deux-là n'ont pas besoin d'être refaits sauf nouveaux agents/photos"
echo "depuis la dernière synchro."
