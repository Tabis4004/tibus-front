#!/usr/bin/env bash
# Applique la marque d'un client puis compile.
#
#   ./tool/build_client.sh sis web
#   ./tool/build_client.sh sis apk
#   ./tool/build_client.sh sis aab
#   ./tool/build_client.sh sis deploy    # build web + mise en ligne Cloudflare
#   ./tool/build_client.sh sis windows
#
# La marque est appliquée AVANT la compilation : c'est ce qui rend impossible
# de livrer un build portant le logo d'un autre client.
set -euo pipefail
cd "$(dirname "$0")/.."

CLIENT="${1:-}"
TARGET="${2:-web}"

if [ -z "$CLIENT" ]; then
  echo "usage : ./tool/build_client.sh <client> [web|apk|aab|windows]" >&2
  echo "clients : $(ls -1 branding 2>/dev/null | tr '\n' ' ')" >&2
  exit 1
fi

python3 tool/apply_brand.py "$CLIENT"

echo
echo "==> Nettoyage (les ressources sont mises en cache par plateforme)"
flutter clean >/dev/null
flutter pub get >/dev/null

# Chaque client a son propre Worker : wrangler.<client>.jsonc. Sans ça,
# `wrangler deploy` publierait ce build par-dessus le site d'un autre client,
# le fichier wrangler.jsonc par défaut étant partagé.
WRANGLER_CONFIG="wrangler.$CLIENT.jsonc"
[ -f "$WRANGLER_CONFIG" ] || WRANGLER_CONFIG="wrangler.jsonc"

echo "==> Compilation : $TARGET"
case "$TARGET" in
  web)     flutter build web --release ;;
  deploy)  flutter build web --release ;;
  apk)     flutter build apk --release ;;
  aab)     flutter build appbundle --release ;;
  windows) flutter build windows --release ;;
  *) echo "cible inconnue : $TARGET" >&2; exit 1 ;;
esac

echo
if [ "$TARGET" = "deploy" ]; then
  echo "==> Mise en ligne ($WRANGLER_CONFIG)"
  npx wrangler deploy -c "$WRANGLER_CONFIG"
fi

echo
echo "Build terminé pour « $CLIENT » ($TARGET)."
case "$TARGET" in
  web) echo "Déploiement : npx wrangler deploy -c $WRANGLER_CONFIG" ;;
  apk) echo "APK : build/app/outputs/flutter-apk/app-release.apk" ;;
  aab) echo "Bundle : build/app/outputs/bundle/release/app-release.aab" ;;
esac
