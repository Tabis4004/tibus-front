#!/usr/bin/env bash
# Récupère la stack officielle Supabase self-hosted (Docker Compose) et la
# place dans ./stack/, prête à configurer.
#
# On ne recopie PAS un docker-compose.yml figé dans ce dépôt : la stack
# officielle change (versions d'images, services) plus vite qu'un fichier
# statique ne peut suivre sans devenir dangereux (images obsolètes /
# vulnérables). Ce script clone toujours la dernière version publiée par
# Supabase, comme documenté sur https://supabase.com/docs/guides/self-hosting/docker
#
# À exécuter SUR LE VPS HOSTINGER (nécessite git + Docker + Docker Compose
# déjà installés sur la machine cible).
#
# Usage :
#   ./00_setup_supabase_stack.sh
set -euo pipefail
cd "$(dirname "$0")"

if [ -d stack ]; then
  echo "./stack existe déjà -- suppression avant nouveau clonage." >&2
  read -p "Continuer ? (o/N) " confirm
  [ "$confirm" = "o" ] || exit 1
  rm -rf stack
fi

TMP="$(mktemp -d)"
git clone --depth 1 https://github.com/supabase/supabase "$TMP"
cp -r "$TMP/docker" ./stack
rm -rf "$TMP"

cp ./stack/.env.example ./stack/.env

echo
echo "Stack clonée dans ./stack/"
echo "Prochaine étape : ./01_configure_env.sh (génère mots de passe/clés) puis"
echo "lire README-docker.md pour les ajustements SIS (services à désactiver,"
echo "reverse proxy, volumes d'init)."
