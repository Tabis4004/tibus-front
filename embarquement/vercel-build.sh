#!/usr/bin/env bash
# Conserve pour compatibilite : le script reel est build-web.sh.
# Ce module se deploie sur Cloudflare Workers, pas sur Vercel.
exec bash "$(dirname "$0")/build-web.sh" "$@"
