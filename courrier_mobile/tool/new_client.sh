#!/usr/bin/env bash
# Crée tout ce qu'il faut pour un nouveau client, côté dépôt.
#
#   ./tool/new_client.sh sis ~/Desktop/logo-sis.png \
#       --nom "SIS Courrier" \
#       --societe "Société SIS" \
#       --domaine courrier.societe-sis.com \
#       --couleur "#1E5A9C"
#
# Ce qui est produit :
#   branding/<client>/brand.json      la marque
#   branding/<client>/<logo>          le logo source
#   branding/<client>/webassets/      favicons et manifest générés
#   wrangler.<client>.jsonc           config du Worker Cloudflare
#
# Ce que le script ne peut PAS faire, et qu'il te rappelle à la fin : créer le
# Worker dans Cloudflare et y attacher le domaine. Ces deux actions passent par
# le dashboard, il n'y a pas d'API sans jeton.
#
# Chaque client a son propre Worker. C'est le point important de cette
# architecture : le nom de l'application, les icônes et le favicon sont
# compilés dans le build, donc un build = une marque = un Worker. Faire servir
# deux domaines par un même Worker les forcerait à partager une marque.
set -euo pipefail
cd "$(dirname "$0")/.."

CLIENT="${1:-}"
LOGO="${2:-}"
shift 2 2>/dev/null || true

NOM=""
SOCIETE=""
DOMAINE=""
COULEUR="#16507A"
PACKAGE=""

while [ $# -gt 0 ]; do
  case "$1" in
    --nom)      NOM="$2"; shift 2 ;;
    --societe)  SOCIETE="$2"; shift 2 ;;
    --domaine)  DOMAINE="$2"; shift 2 ;;
    --couleur)  COULEUR="$2"; shift 2 ;;
    --package)  PACKAGE="$2"; shift 2 ;;
    *) echo "option inconnue : $1" >&2; exit 1 ;;
  esac
done

usage() {
  cat >&2 <<'EOF'
usage : ./tool/new_client.sh <client> <chemin/du/logo> [options]

  <client>      identifiant court, minuscules, sans espace (ex. sis)
                sert de nom de dossier, de suffixe de config et de nom de Worker

options
  --nom      "SIS Courrier"          nom affiché dans l'app et l'onglet
  --societe  "Société SIS"           éditeur, visible dans l'installateur Windows
  --domaine  courrier.exemple.com    domaine prévu (rappel en fin de script)
  --couleur  "#1E5A9C"               couleur de thème PWA
  --package  com.exemple             identifiant société (CompanyName Windows)
EOF
  exit 1
}

[ -n "$CLIENT" ] && [ -n "$LOGO" ] || usage

# Le nom du client devient un nom de Worker Cloudflare et un nom de dossier :
# les majuscules, espaces et underscores y sont refusés ou source de confusion.
if ! printf '%s' "$CLIENT" | grep -qE '^[a-z0-9][a-z0-9-]*$'; then
  echo "Nom de client invalide : « $CLIENT »" >&2
  echo "Attendu : minuscules, chiffres et tirets (ex. sis, groupe-ktm)." >&2
  exit 1
fi

if [ "$CLIENT" = "default" ]; then
  echo "« default » est la marque Tibus, elle existe déjà." >&2
  exit 1
fi

[ -f "$LOGO" ] || { echo "Logo introuvable : $LOGO" >&2; exit 1; }

DEST="branding/$CLIENT"
if [ -d "$DEST" ]; then
  echo "$DEST existe déjà. Supprime-le ou choisis un autre identifiant." >&2
  exit 1
fi

# Valeurs par défaut déduites de l'identifiant, pour que le script marche même
# sans aucune option.
NOM="${NOM:-$(printf '%s' "$CLIENT" | tr '[:lower:]' '[:upper:]') Courrier}"
SOCIETE="${SOCIETE:-$NOM}"
PACKAGE="${PACKAGE:-com.$CLIENT}"

EXT="${LOGO##*.}"
mkdir -p "$DEST"
cp "$LOGO" "$DEST/logo.$EXT"

# brand.json écrit par python, et les valeurs passées en arguments plutôt
# qu'interpolées dans le source : un nom de société contenant une apostrophe
# ou un guillemet — « Société d'Import », c'est courant — casserait un
# heredoc, et `cat` n'échapperait rien du tout dans le JSON.
python3 - "$DEST/brand.json" "$NOM" "$COULEUR" "$PACKAGE" "logo.$EXT" \
         "courrier-$CLIENT" "$SOCIETE" <<'PY'
import json, sys
out, nom, couleur, package, logo, worker, societe = sys.argv[1:8]
brand = {
    "appName": nom,
    "shortName": nom,
    "description": f"{nom} — suivi et gestion de colis.",
    "themeColor": couleur,
    "backgroundColor": "#FFFFFF",
    "companyId": package,
    "logo": logo,
    "iconBackground": "#FFFFFF",
    "iconPadding": 0.08,
    "worker": worker,
    "publisher": societe,
}
with open(out, "w", encoding="utf-8") as f:
    json.dump(brand, f, indent=2, ensure_ascii=False)
    f.write("\n")
PY

# Un Worker par client : sans ça, `wrangler deploy` publierait ce build
# par-dessus le site d'un autre client, wrangler.jsonc étant partagé.
cat > "wrangler.$CLIENT.jsonc" <<EOF
{
  "\$schema": "node_modules/wrangler/config-schema.json",
  // Worker dédié à $SOCIETE. Le nom doit correspondre au Worker créé dans
  // Cloudflare, sinon \`wrangler deploy\` en crée un second silencieusement.
  "name": "courrier-$CLIENT",
  "compatibility_date": "$(date +%Y-%m-%d)",
  "observability": { "enabled": true },
  "assets": {
    "directory": "./build/web",
    // L'application est une SPA : toute URL inconnue doit rendre index.html,
    // sinon un rechargement sur une route interne renvoie une 404.
    "not_found_handling": "single-page-application"
  }
}
EOF

# Génère favicons, icônes et webassets, puis remet la marque Tibus : le dépôt
# ne doit pas rester branché sur un client, ses icônes étant versionnées.
python3 tool/apply_brand.py "$CLIENT" >/dev/null
python3 tool/apply_brand.py default >/dev/null

cat <<EOF

Client « $CLIENT » créé.

  $DEST/brand.json
  $DEST/logo.$EXT
  $DEST/webassets/            $(find "$DEST/webassets" -type f 2>/dev/null | wc -l | tr -d ' ') fichiers
  wrangler.$CLIENT.jsonc      Worker « courrier-$CLIENT »

La marque du dépôt est revenue à « default » (Tibus). Vérifie brand.json,
notamment appName et themeColor, puis commite et pousse.

Reste à faire dans Cloudflare, une seule fois par client :

  1. Workers & Pages -> Create application -> Workers -> Import a repository
     Dépôt Tabis4004/tibus-front
     Nom du Worker      courrier-$CLIENT
     Root directory     courrier_mobile
     Build command      ./vercel-build.sh
     Deploy command     npx wrangler deploy -c wrangler.$CLIENT.jsonc

  2. Settings -> Variables and Secrets -> Add
     BRAND = $CLIENT

     Sans cette variable le build sortirait avec la marque Tibus. C'est le
     défaut voulu : ta marque par défaut, chaque client s'y ajoute
     explicitement.

  3. Settings -> Domains & Routes -> Add -> Custom domain
     ${DOMAINE:-<le domaine du client>}

Builds locaux :

  ./tool/build_client.sh $CLIENT web
  ./tool/build_client.sh $CLIENT deploy
  ./tool/build_client.sh $CLIENT apk

Build Windows : GitHub -> Actions -> Build Courrier Mobile Windows -> $CLIENT
EOF
