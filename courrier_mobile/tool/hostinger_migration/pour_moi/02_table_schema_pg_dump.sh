#!/usr/bin/env bash
# Export du SCHÉMA (structure seule, pas les données) des tables du
# périmètre colis/guichet/bordereau SIS, depuis Tibus 1.0.
#
# Nécessite pg_dump (installé avec PostgreSQL / Postgres.app / `brew
# install postgresql`). Renseigner la connection string ci-dessous : elle
# se trouve sur le dashboard Supabase du projet "Tibus 1.0"
# (kqudaqtydimjclwaihqr) > Project Settings > Database > Connection string
# (mode "Session pooler" ou "Direct connection" conviennent, PAS "Transaction
# pooler" pour pg_dump).
#
# Usage :
#   TIBUS1_DB_URL="postgresql://postgres.xxxx:MOTDEPASSE@...supabase.com:5432/postgres" \
#     ./02_table_schema_pg_dump.sh
set -euo pipefail

if [ -z "${TIBUS1_DB_URL:-}" ]; then
  echo "Renseigner TIBUS1_DB_URL (voir commentaire en tête de ce script)." >&2
  exit 1
fi

OUT="../pour_technicien/sis_schema_tables.sql"

# Périmètre établi par l'audit du 2026-08-09, complété le 2026-08-23
# ("Cities" ajoutée -- référencée par list_company_villes_depart, appelée
# par colis_service.dart, absente de l'audit initial) -- voir
# 01_generate_functions_and_triggers.sql pour le détail du raisonnement.
# --schema-only : structure (colonnes, contraintes, index, séquences,
# policies RLS) sans les données -- les données sont exportées séparément
# et filtrées sur la compagnie SIS (voir 03_export_sis_data.sh).
pg_dump "$TIBUS1_DB_URL" \
  --schema-only \
  --no-owner --no-privileges \
  -n public \
  -t '"Countries"' \
  -t '"Cities"' \
  -t '"Companies"' \
  -t '"CompanyFeatureModules"' \
  -t '"CompanyExpenseCategory"' \
  -t '"Users"' \
  -t '"UserRoles"' \
  -t '"Role"' \
  -t '"Gares"' \
  -t '"Bus"' \
  -t 'colis_autonomes' \
  -t 'colis_natures' \
  -t 'colis_natures_selectionnees' \
  -t 'colis_numerotation_gares' \
  -t 'caisses_gares' \
  -t '"Notifications"' \
  -t '"DeviceTokens"' \
  -t '"ColisTrackingSubscriptions"' \
  -t '"ContactSettings"' \
  -f "$OUT"

echo "Écrit : $OUT"
echo
echo "ATTENTION avant de rejouer sur Hostinger :"
echo "  - --no-owner --no-privileges retire les GRANT/OWNER spécifiques à"
echo "    Supabase (rôles authenticated/anon/service_role) : sur la nouvelle"
echo "    instance self-hosted, ces rôles existent déjà nativement (créés"
echo "    par la stack Supabase self-host) -- pas d'action requise, mais si"
echo "    RLS ne s'applique pas comme attendu, vérifier les GRANT manquants."
echo "  - Rejouer AVANT 01_generate_functions_and_triggers.sql (les triggers"
echo "    référencent des fonctions qui doivent déjà exister... en fait"
echo "    l'ordre n'a pas d'importance pour les FONCTIONS (PL/pgSQL ne"
echo "    valide pas les dépendances à la création), mais les TRIGGERS eux-"
echo "    mêmes ne peuvent être créés qu'une fois la table ET la fonction"
echo "    présentes : donc schéma table -> fonctions -> triggers (déjà"
echo "    l'ordre du fichier 01)."
