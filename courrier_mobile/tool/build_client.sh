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

# --dart-define dérivés de branding/<client>/brand.json (URL/clé Supabase
# propres à ce client si définies, bascules de fonctionnalités par marque)
# — voir tool/brand_dart_defines.py. Vide pour tout client qui ne définit
# rien dans brand.json : comportement inchangé (repli sur Tibus 1.0).
#
# Chaîne (pas un tableau bash) + expansion NON quotée volontaire ci-dessous :
# évite le piège classique "tableau vide + set -u" qui plante sous le
# /bin/bash 3.2 encore livré par défaut sur macOS (corrigé seulement en
# bash >= 4.4). Sûr ici : les tokens --dart-define=CLE=VALEUR ne contiennent
# pas d'espace.
DART_DEFINES="$(python3 tool/brand_dart_defines.py "$CLIENT" | tr '\n' ' ')"
if [ -n "$DART_DEFINES" ]; then
  echo "==> --dart-define spécifiques à « $CLIENT » : $DART_DEFINES"
fi

echo "==> Compilation : $TARGET"
case "$TARGET" in
  web)     flutter build web --release $DART_DEFINES ;;
  deploy)  flutter build web --release $DART_DEFINES ;;
  apk)     flutter build apk --release $DART_DEFINES ;;
  aab)     flutter build appbundle --release $DART_DEFINES ;;
  windows) flutter build windows --release $DART_DEFINES ;;
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
