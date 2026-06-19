#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
./scripts/supabase-project-check.sh
if [[ -z "${SUPABASE_DB_PASSWORD:-}" ]]; then
  echo "ERREUR : export SUPABASE_DB_PASSWORD='...' (Dashboard → Database password)" >&2
  exit 1
fi
POOLER_URL="$(cat supabase/.temp/pooler-url 2>/dev/null || echo 'postgresql://postgres.kqudaqtydimjclwaihqr@aws-0-eu-west-1.pooler.supabase.com:5432/postgres')"
MODE="${1:-execute}"
if [[ "$MODE" == "dry-run" ]]; then
  echo "=== DRY-RUN (ROLLBACK) ==="
  (cat scripts/prod-cleanup-execute.sql; echo "ROLLBACK;") | sed 's/^COMMIT;$/ROLLBACK;/' | PGPASSWORD="$SUPABASE_DB_PASSWORD" psql "$POOLER_URL" -v ON_ERROR_STOP=1
else
  echo "=== PURGE PROD dans 5s (Ctrl+C annule) ==="
  sleep 5
  PGPASSWORD="$SUPABASE_DB_PASSWORD" psql "$POOLER_URL" -v ON_ERROR_STOP=1 -f scripts/prod-cleanup-execute.sql
fi
