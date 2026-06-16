#!/usr/bin/env bash
# Vérifie que la CLI Supabase / .env.local pointent sur Tibus 1.0 (pas TabisPay).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TARGET_FILE="$ROOT/supabase/project.target.json"

if [[ ! -f "$TARGET_FILE" ]]; then
  echo "ERREUR : $TARGET_FILE introuvable." >&2
  exit 1
fi

EXPECTED_REF="$(python3 -c "import json; print(json.load(open('$TARGET_FILE'))['target']['ref'])")"
EXPECTED_NAME="$(python3 -c "import json; print(json.load(open('$TARGET_FILE'))['target']['name'])")"
EXPECTED_URL="$(python3 -c "import json; print(json.load(open('$TARGET_FILE'))['target']['url'])")"

LINKED_REF="$(cat "$ROOT/supabase/.temp/project-ref" 2>/dev/null || echo "")"
ENV_FILE="$ROOT/.env.local"
ENV_URL=""
if [[ -f "$ENV_FILE" ]]; then
  ENV_URL="$(grep -E '^VITE_SUPABASE_URL=' "$ENV_FILE" | cut -d= -f2- | tr -d '"' | tr -d "'")"
fi

echo "── Projets (éviter le mélange) ──"
echo "  ✓ Cible tibus-front : $EXPECTED_NAME ($EXPECTED_REF)"
python3 -c "
import json
for p in json.load(open('$TARGET_FILE')).get('forbidden', []):
    print(f\"  ✗ Interdit ici      : {p['name']} ({p['ref']})\")
    print(f\"    → {p['reason']}\")
for p in json.load(open('$TARGET_FILE')).get('otherProjects', []):
    print(f\"  ○ Autre stack       : {p['name']} — {p.get('stack','')}\")
"
echo ""

FAIL=0

if [[ -z "$LINKED_REF" ]]; then
  echo "⚠ CLI non liée. Exécutez : ./scripts/supabase-link-tibus.sh" >&2
  FAIL=1
elif [[ "$LINKED_REF" != "$EXPECTED_REF" ]]; then
  echo "ERREUR : supabase link = $LINKED_REF (attendu $EXPECTED_REF)." >&2
  echo "       → ./scripts/supabase-link-tibus.sh" >&2
  FAIL=1
else
  echo "✓ CLI liée : $LINKED_REF"
fi

if [[ -n "$ENV_URL" && "$ENV_URL" != "$EXPECTED_URL" ]]; then
  echo "ERREUR : VITE_SUPABASE_URL=$ENV_URL" >&2
  echo "       attendu $EXPECTED_URL (.env.local = mauvais projet ?)" >&2
  FAIL=1
elif [[ -n "$ENV_URL" ]]; then
  echo "✓ .env.local URL : $ENV_URL"
fi

if [[ -f "$ENV_FILE" ]]; then
  ANON="$(grep -E '^VITE_SUPABASE_ANON_KEY=' "$ENV_FILE" | cut -d= -f2- | tr -d '"' | tr -d "'")"
  if [[ -n "$ANON" && -n "$ENV_URL" ]]; then
    HTTP="$(curl -s -o /dev/null -w "%{http_code}" "$ENV_URL/rest/v1/Users?select=id&limit=1" \
      -H "apikey: $ANON" -H "Authorization: Bearer $ANON")"
    if [[ "$HTTP" != "200" ]]; then
      echo "ERREUR : table Users inaccessible (HTTP $HTTP) sur $ENV_URL." >&2
      echo "       Vous êtes probablement sur TabisPay ou une base vide." >&2
      FAIL=1
    else
      echo "✓ Schéma Tibus : table Users OK (REST)"
    fi
  fi
fi

if [[ "$FAIL" -ne 0 ]]; then
  exit 1
fi

echo ""
echo "OK — environnement Tibus 1.0 cohérent."
