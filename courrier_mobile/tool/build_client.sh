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
# Un token par ligne, lu dans un tableau : les valeurs peuvent contenir des
# espaces (ex. BRAND_NAME=SIS COURRIER). Lecture par `while read` (pas
# `mapfile`, absent du /bin/bash 3.2 de macOS) et expansion
# ${DART_DEFINES[@]+"${DART_DEFINES[@]}"} : sûre avec `set -u` même quand le
# tableau est vide (piège classique de bash < 4.4).
DART_DEFINES=()
while IFS= read -r line; do
  if [ -n "$line" ]; then DART_DEFINES+=("$line"); fi
done < <(python3 tool/brand_dart_defines.py "$CLIENT")
if [ ${#DART_DEFINES[@]} -gt 0 ]; then
  echo "==> --dart-define spécifiques à « $CLIENT » :"
  printf '    %s\n' "${DART_DEFINES[@]}"
fi

# Play Store exige un versionCode strictement croissant à chaque envoi, PAR
# APP (donc un compteur indépendant pour SIS et pour Tibus, vu que ce sont
# deux applicationId différents depuis le passage en Play Store séparé).
# BUILD_NUMBER (optionnel, ex. github.run_number côté CI) écrase le +N de
# pubspec.yaml pour ce build précis, SANS modifier le fichier -- en local,
# sans cette variable, comportement inchangé (numéro de pubspec.yaml).
#
# En local (sans BUILD_NUMBER), pour apk/aab, le numéro est incrémenté
# automatiquement par marque via tool/bump_version_code.py (compteur dans
# branding/<client>/version_code -- à committer après chaque envoi Play).
EXTRA_BUILD_ARGS=""
if [ -n "${BUILD_NUMBER:-}" ]; then
  EXTRA_BUILD_ARGS="--build-number=$BUILD_NUMBER"
  echo "==> --build-number=$BUILD_NUMBER (fourni par l'environnement, ex. CI)"
elif [ "$TARGET" = "apk" ] || [ "$TARGET" = "aab" ]; then
  BUILD_NUMBER="$(python3 tool/bump_version_code.py "$CLIENT")"
  EXTRA_BUILD_ARGS="--build-number=$BUILD_NUMBER"
  echo "==> versionCode auto « $CLIENT » : $BUILD_NUMBER (branding/$CLIENT/version_code)"
fi

echo "==> Compilation : $TARGET"
case "$TARGET" in
  web)     flutter build web --release ${DART_DEFINES[@]+"${DART_DEFINES[@]}"} ;;
  deploy)  flutter build web --release ${DART_DEFINES[@]+"${DART_DEFINES[@]}"} ;;
  apk)     flutter build apk --release ${DART_DEFINES[@]+"${DART_DEFINES[@]}"} $EXTRA_BUILD_ARGS ;;
  aab)     flutter build appbundle --release ${DART_DEFINES[@]+"${DART_DEFINES[@]}"} $EXTRA_BUILD_ARGS ;;
  windows) flutter build windows --release ${DART_DEFINES[@]+"${DART_DEFINES[@]}"} ;;
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
