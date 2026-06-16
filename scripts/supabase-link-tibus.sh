#!/usr/bin/env bash
# Re-lie explicitement la CLI Supabase au projet Tibus 1.0.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

REF="$(python3 -c "import json; print(json.load(open('supabase/project.target.json'))['target']['ref'])")"
NAME="$(python3 -c "import json; print(json.load(open('supabase/project.target.json'))['target']['name'])")"

echo "→ Liaison Supabase CLI → $NAME ($REF)"
echo "  (ignorez TabisPay lxgzgkeibtqfuzpjizrv pour ce dépôt)"
echo ""

supabase link --project-ref "$REF"

echo ""
"$(dirname "$0")/supabase-project-check.sh"
