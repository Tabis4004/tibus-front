#!/usr/bin/env bash
# Déploiement production Tibus sur Vercel
# Usage :
#   ./deploy-vercel.sh          # via GitHub (auto-build Vercel)
#   ./deploy-vercel.sh --cli    # déploiement direct avec Vercel CLI

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

MODE="${1:-git}"

echo "→ Projet : $ROOT"
echo "→ Branche : $(git branch --show-current)"

if [[ "$MODE" == "--cli" ]]; then
  echo "→ Build local de vérification..."
  npm ci
  npm run build

  echo "→ Déploiement production Vercel (via npx, sans install globale)..."
  if [[ ! -f .vercel/project.json ]]; then
    echo "→ Liaison au projet Vercel (une seule fois)..."
    npx vercel link
  fi

  npx vercel --prod
  echo "✓ Déployé via Vercel CLI."
  exit 0
fi

echo "→ Récupération des dernières modifications..."
git fetch origin main
git checkout main
git pull --ff-only origin main

echo "→ Statut git :"
git status --short

echo "→ Push vers GitHub (déclenche le build Vercel si le repo est connecté)..."
git push origin main

echo ""
echo "✓ Push terminé."
echo "  Suivez le déploiement : https://vercel.com/dashboard"
echo "  Site production       : https://tibus.app"
echo ""
echo "Astuce : pour déployer sans commit, lancez : ./deploy-vercel.sh --cli"
