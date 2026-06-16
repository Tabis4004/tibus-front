#!/usr/bin/env bash
# Migrations SQL Tibus → UNIQUEMENT Supabase Tibus 1.0 (pas TabisPay, pas Gestabis).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

"$(dirname "$0")/supabase-project-check.sh" || exit 1

echo ""
echo "→ Application des migrations (supabase db push)…"
supabase db push --linked --yes

echo "✓ Migrations Tibus 1.0 appliquées."
