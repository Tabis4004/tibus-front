#!/usr/bin/env bash
# Déploiement production du site web Tibus (tibus-front) sur Cloudflare Workers.
#
# Usage :
#   ./deploy-cloudflare.sh          # push sur main : Cloudflare construit et déploie (Workers Builds)
#   ./deploy-cloudflare.sh --cli    # build local puis déploiement direct avec wrangler
#
# Configuration : wrangler.jsonc (worker "tibus-front", fichiers statiques de ./dist).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

echo "→ Projet : $ROOT"
echo "→ Branche : $(git branch --show-current)"

if [[ "${1:-}" == "--cli" ]]; then
  echo "→ Installation des dépendances..."
  npm ci
  echo "→ Build..."
  npm run build
  echo "→ Déploiement Cloudflare (wrangler)..."
  npx wrangler deploy
  echo "✓ Déployé sur Cloudflare."
  exit 0
fi

echo "→ Push vers GitHub (déclenche le build Cloudflare)..."
git push origin main
echo "✓ Push terminé. Suivi : tableau de bord Cloudflare → Workers & Pages → tibus-front → Deployments."
