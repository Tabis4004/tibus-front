#!/usr/bin/env bash
# Génère des secrets propres à cette instance (mot de passe Postgres, JWT
# secret, clés anon/service_role dérivées de ce JWT secret) et les écrit
# dans ./stack/.env, à la place des valeurs d'exemple du dépôt Supabase
# (qui sont PUBLIQUES -- documentées telles quelles dans leur README --
# donc à ne jamais utiliser telles quelles en production).
#
# Nécessite python3 (stdlib uniquement, pas de dépendance à installer).
#
# Usage :
#   ./01_configure_env.sh
set -euo pipefail
cd "$(dirname "$0")"

ENV_FILE="stack/.env"
if [ ! -f "$ENV_FILE" ]; then
  echo "$ENV_FILE introuvable -- lancer 00_setup_supabase_stack.sh d'abord." >&2
  exit 1
fi

POSTGRES_PASSWORD="$(openssl rand -hex 24)"
JWT_SECRET="$(openssl rand -hex 32)"
DASHBOARD_PASSWORD="$(openssl rand -hex 12)"

read -r -d '' KEYS_PY <<'PYEOF' || true
import base64, hashlib, hmac, json, sys, time

secret = sys.argv[1]

def b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b'=').decode()

def make_jwt(role: str) -> str:
    header = {"alg": "HS256", "typ": "JWT"}
    now = int(time.time())
    payload = {
        "role": role,
        "iss": "supabase",
        "iat": now,
        # 10 ans -- ce sont des clés d'API internes à l'infrastructure du
        # client, pas des jetons utilisateur ; leur rotation se fait en
        # relançant ce script si besoin, pas sur une base calendaire courte.
        "exp": now + 10 * 365 * 24 * 3600,
    }
    signing_input = b64url(json.dumps(header, separators=(',', ':')).encode()) + '.' + \
                    b64url(json.dumps(payload, separators=(',', ':')).encode())
    sig = hmac.new(secret.encode(), signing_input.encode(), hashlib.sha256).digest()
    return signing_input + '.' + b64url(sig)

print(make_jwt("anon"))
print(make_jwt("service_role"))
PYEOF

readarray -t KEYS < <(python3 -c "$KEYS_PY" "$JWT_SECRET")
ANON_KEY="${KEYS[0]}"
SERVICE_ROLE_KEY="${KEYS[1]}"

set_env() {
  local key="$1" value="$2"
  if grep -q "^${key}=" "$ENV_FILE"; then
    # Utilise | comme séparateur sed : les valeurs (base64/hex) ne
    # contiennent jamais de |, contrairement à / qui apparaît dans le JWT.
    sed -i.bak "s|^${key}=.*|${key}=${value}|" "$ENV_FILE"
  else
    echo "${key}=${value}" >> "$ENV_FILE"
  fi
}

set_env "POSTGRES_PASSWORD" "$POSTGRES_PASSWORD"
set_env "JWT_SECRET" "$JWT_SECRET"
set_env "ANON_KEY" "$ANON_KEY"
set_env "SERVICE_ROLE_KEY" "$SERVICE_ROLE_KEY"
set_env "DASHBOARD_USERNAME" "sis-admin"
set_env "DASHBOARD_PASSWORD" "$DASHBOARD_PASSWORD"
rm -f "$ENV_FILE.bak"

echo "Secrets générés et écrits dans $ENV_FILE."
echo
echo "À NOTER (affiché une seule fois, pas stocké ailleurs par ce script) :"
echo "  DASHBOARD_USERNAME = sis-admin"
echo "  DASHBOARD_PASSWORD = $DASHBOARD_PASSWORD"
echo "  ANON_KEY            (dans $ENV_FILE)"
echo "  SERVICE_ROLE_KEY    (dans $ENV_FILE)"
echo
echo "Reste à renseigner MANUELLEMENT dans $ENV_FILE avant de démarrer :"
echo "  - SITE_URL, API_EXTERNAL_URL, SUPABASE_PUBLIC_URL : domaine réel du"
echo "    VPS Hostinger (ex. https://api.sis-colis.example.com)."
echo "  - SMTP_* : uniquement si des emails (reset mot de passe agent) sont"
echo "    nécessaires -- sinon laisser les valeurs d'exemple, non utilisées."
echo
echo "ANON_KEY et SERVICE_ROLE_KEY générées ici devront ensuite être"
echo "reportées dans courrier_mobile/branding/sis/brand.json"
echo "(supabaseUrl / supabaseAnonKey -- voir README.md du dossier parent)."
echo
echo "Prochaine étape : lire README-docker.md avant \`docker compose up -d\`."
