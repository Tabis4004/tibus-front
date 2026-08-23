#!/usr/bin/env bash
# Vérifie que le paquet ../pour_technicien/ est complet (schéma, fonctions/
# triggers non vide, données) puis le zippe, prêt à envoyer au technicien
# SIS. N'ajoute rien qui ne soit déjà dans pour_technicien/ -- ne touche
# jamais au reste du dépôt tibus-front.
#
# Usage :
#   ./04_zip_pour_technicien.sh
set -euo pipefail
cd "$(dirname "$0")/../pour_technicien"

MISSING=()
[ -s sis_schema_tables.sql ] || MISSING+=("sis_schema_tables.sql absent ou vide (lancer ../pour_moi/02_table_schema_pg_dump.sh)")
if [ ! -s functions_and_triggers.sql ] || grep -q '^-- PLACEHOLDER' functions_and_triggers.sql; then
  MISSING+=("functions_and_triggers.sql encore vide/placeholder (voir ../pour_moi/README.md étape 2)")
fi
[ -d sis_export ] && [ -n "$(ls -A sis_export 2>/dev/null)" ] || MISSING+=("sis_export/ absent ou vide (lancer ../pour_moi/03_export_sis_data.sh)")

if [ "${#MISSING[@]}" -gt 0 ]; then
  echo "Paquet incomplet -- il manque :" >&2
  for m in "${MISSING[@]}"; do echo "  - $m" >&2; done
  exit 1
fi

ZIP="../paquet_technicien_sis.zip"
rm -f "$ZIP"
zip -r "$ZIP" . -x ".DS_Store" -x "stack/*" >/dev/null

echo "Paquet prêt : $(cd .. && pwd)/paquet_technicien_sis.zip"
echo
echo "Contenu :"
# `head -n -N` est une extension GNU absente du `head` livré par défaut sur
# macOS (BSD) -- on filtre plutôt les lignes de contenu de `unzip -l`
# (elles commencent toutes par la taille en octets), portable partout.
unzip -l "$ZIP" | grep -E '^ *[0-9]'
