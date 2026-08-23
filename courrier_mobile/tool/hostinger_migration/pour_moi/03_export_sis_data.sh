#!/usr/bin/env bash
# Export des DONNÉES de SIS uniquement (companyId =
# 1422ab71-4a45-45af-8e7c-4c72a2f9b296, confirmé sur Tibus 1.0 le
# 2026-08-09) depuis Tibus 1.0, une CSV par table, directement dans
# ../pour_technicien/sis_export/ (le paquet à envoyer, pas ici).
#
# Usage :
#   TIBUS1_DB_URL="postgresql://postgres.xxxx:MOTDEPASSE@...supabase.com:5432/postgres" \
#     ./03_export_sis_data.sh
set -euo pipefail

if [ -z "${TIBUS1_DB_URL:-}" ]; then
  echo "Renseigner TIBUS1_DB_URL (voir 02_table_schema_pg_dump.sh)." >&2
  exit 1
fi

SIS_ID="1422ab71-4a45-45af-8e7c-4c72a2f9b296"
OUT_DIR="../pour_technicien/sis_export"
mkdir -p "$OUT_DIR"

copy() {
  local file="$1" query="$2"
  echo "==> $file"
  psql "$TIBUS1_DB_URL" -c "\copy ($query) TO '$OUT_DIR/$file' WITH CSV HEADER"
}

# Ordre indifférent à l'export (lecture seule) — l'ordre compte à
# l'IMPORT (voir 04_import_data.sh, qui neutralise triggers/FK pendant le
# chargement, donc l'ordre n'y compte pas non plus en pratique).

# Tables de référence globales, exportées EN ENTIER (pas propres à SIS) :
copy "Countries.csv"            'SELECT * FROM "Countries"'
copy "Cities.csv"               'SELECT * FROM "Cities"'
copy "Role.csv"                 'SELECT * FROM "Role"'
copy "ContactSettings.csv"      'SELECT * FROM "ContactSettings"'

# Compagnie SIS et ses dépendances directes :
copy "Companies.csv"            "SELECT * FROM \"Companies\" WHERE id = '$SIS_ID'"
copy "CompanyFeatureModules.csv" "SELECT * FROM \"CompanyFeatureModules\" WHERE \"companyId\" = '$SIS_ID'"
copy "CompanyExpenseCategory.csv" "SELECT * FROM \"CompanyExpenseCategory\" WHERE \"companyId\" = '$SIS_ID'"

# Utilisateurs ayant au moins un rôle chez SIS (et leurs rôles eux-mêmes) :
copy "Users.csv" "SELECT * FROM \"Users\" WHERE id IN (SELECT \"userId\" FROM \"UserRoles\" WHERE \"companyId\" = '$SIS_ID')"
copy "UserRoles.csv" "SELECT * FROM \"UserRoles\" WHERE \"companyId\" = '$SIS_ID'"

# Gares, bus, caisses :
copy "Gares.csv" "SELECT * FROM \"Gares\" WHERE \"companyId\" = '$SIS_ID'"
copy "Bus.csv"   "SELECT * FROM \"Bus\" WHERE \"companyId\" = '$SIS_ID'"
copy "caisses_gares.csv" "SELECT * FROM caisses_gares WHERE gare_id IN (SELECT id FROM \"Gares\" WHERE \"companyId\" = '$SIS_ID')"

# Colis + dépendances :
copy "colis_natures.csv" "SELECT * FROM colis_natures WHERE company_id = '$SIS_ID'"
copy "colis_autonomes.csv" "SELECT * FROM colis_autonomes WHERE company_id = '$SIS_ID'"
copy "colis_natures_selectionnees.csv" "SELECT * FROM colis_natures_selectionnees WHERE colis_id IN (SELECT id FROM colis_autonomes WHERE company_id = '$SIS_ID')"
copy "colis_numerotation_gares.csv" "SELECT * FROM colis_numerotation_gares WHERE gare_id IN (SELECT id FROM \"Gares\" WHERE \"companyId\" = '$SIS_ID')"

# Notifications / appareils / suivi, rattachés aux utilisateurs SIS :
copy "Notifications.csv" "SELECT * FROM \"Notifications\" WHERE \"userId\" IN (SELECT \"userId\" FROM \"UserRoles\" WHERE \"companyId\" = '$SIS_ID')"
copy "DeviceTokens.csv" "SELECT * FROM \"DeviceTokens\" WHERE \"userId\" IN (SELECT \"userId\" FROM \"UserRoles\" WHERE \"companyId\" = '$SIS_ID')"
copy "ColisTrackingSubscriptions.csv" "SELECT * FROM \"ColisTrackingSubscriptions\" WHERE \"colisId\" IN (SELECT id FROM colis_autonomes WHERE company_id = '$SIS_ID')"

echo
echo "Terminé. $OUT_DIR/ contient un .csv par table, prêt pour 04_import_data.sh."
echo
echo "NON couvert par ce script (à faire séparément) :"
echo "  - Comptes de connexion (auth.users, GoTrue) -- voir README.md."
echo "  - Photos de colis (bucket Storage \"colis-photos\") -- fichiers, pas"
echo "    des lignes SQL. Lister les chemins via :"
echo "      SELECT id, photo_path FROM colis_autonomes WHERE company_id = '$SIS_ID' AND photo_path IS NOT NULL;"
echo "    puis les télécharger un par un (Storage API ou dashboard) et les"
echo "    ré-uploader sur le bucket \"colis-photos\" de la nouvelle instance."
