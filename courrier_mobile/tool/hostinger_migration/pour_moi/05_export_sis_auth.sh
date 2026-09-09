#!/usr/bin/env bash
# Export SCOPÉ des comptes de connexion (GoTrue) des agents SIS
# UNIQUEMENT -- PAS un export de auth.users/auth.identities en entier.
#
# Pourquoi le scope est indispensable : auth.users sur Tibus 1.0 est une
# table GLOBALE, partagée par toute la plateforme (agents Tibus,
# courrier_livreur, courrier_client, toutes les autres compagnies bus) --
# elle contient leurs hash de mot de passe. Un export complet donnerait au
# technicien SIS les identifiants chiffrés de gens qui n'ont rien à voir
# avec SIS. Ce script ne prend que les lignes dont l'id correspond à
# "Users".auth_user_id pour les utilisateurs ayant un rôle chez SIS
# (companyId = 1422ab71-4a45-45af-8e7c-4c72a2f9b296) -- la requête est
# dynamique, donc le nombre d'agents suit automatiquement les recrutements
# (29 au 2026-08-28, contre 25 au 2026-08-23 -- vérifié à nouveau ce jour :
# toujours 29/29 users avec auth_user_id renseigné, 29/29 retrouvés dans
# auth.users, 29/29 dans auth.identities, aucun écart).
#
# Colonnes GÉNÉRÉES exclues explicitement (Postgres refuse un INSERT/COPY
# dessus, vérifié sur le schéma live du 2026-08-23) :
#   - auth.users.confirmed_at       (= LEAST(email_confirmed_at, phone_confirmed_at))
#   - auth.identities.email         (dérivée de identity_data->>'email')
#
# SENSIBLE : contient des hash de mot de passe (bcrypt) et jetons de
# récupération/confirmation. Écrit dans ./sis_auth_SENSIBLE/, un dossier
# volontairement séparé de pour_technicien/ (jamais inclus dans le zip
# automatique de 04_zip_pour_technicien.sh) et listé dans .gitignore --
# ne JAMAIS committer ce dossier. À transmettre au technicien par un canal
# que tu juges sûr (pas un email en clair), puis à supprimer localement une
# fois le transfert confirmé.
#
# Usage :
#   TIBUS1_DB_URL="postgresql://postgres.xxxx:MOTDEPASSE@...supabase.com:5432/postgres" \
#     ./05_export_sis_auth.sh
set -euo pipefail

if [ -z "${TIBUS1_DB_URL:-}" ]; then
  echo "Renseigner TIBUS1_DB_URL (voir 02_table_schema_pg_dump.sh)." >&2
  exit 1
fi

SIS_ID="1422ab71-4a45-45af-8e7c-4c72a2f9b296"
OUT_DIR="sis_auth_SENSIBLE"
mkdir -p "$OUT_DIR"

SIS_AUTH_IDS="(SELECT auth_user_id FROM \"Users\" WHERE id IN (SELECT \"userId\" FROM \"UserRoles\" WHERE \"companyId\" = '$SIS_ID') AND auth_user_id IS NOT NULL)"

echo "==> auth_users.csv"
psql "$TIBUS1_DB_URL" -c "\copy (
  SELECT instance_id, id, aud, role, email, encrypted_password,
         email_confirmed_at, invited_at, confirmation_token,
         confirmation_sent_at, recovery_token, recovery_sent_at,
         email_change_token_new, email_change, email_change_sent_at,
         last_sign_in_at, raw_app_meta_data, raw_user_meta_data,
         is_super_admin, created_at, updated_at, phone,
         phone_confirmed_at, phone_change, phone_change_token,
         phone_change_sent_at, email_change_token_current,
         email_change_confirm_status, banned_until,
         reauthentication_token, reauthentication_sent_at,
         is_sso_user, deleted_at, is_anonymous
  FROM auth.users
  WHERE id IN $SIS_AUTH_IDS
) TO '$OUT_DIR/auth_users.csv' WITH CSV HEADER"

echo "==> auth_identities.csv"
psql "$TIBUS1_DB_URL" -c "\copy (
  SELECT provider_id, user_id, identity_data, provider,
         last_sign_in_at, created_at, updated_at, id
  FROM auth.identities
  WHERE user_id IN $SIS_AUTH_IDS
) TO '$OUT_DIR/auth_identities.csv' WITH CSV HEADER"

cat > "$OUT_DIR/IMPORT_INSTRUCTIONS.md" <<'EOF'
# Import des comptes agents SIS (auth.users / auth.identities)

SENSIBLE -- contient des hash de mot de passe. À exécuter par le
technicien SIS, sur le VPS, directement contre l'instance Hostinger.
Supprimer ces fichiers du disque une fois l'import fait et vérifié.

## Ordre (users avant identities -- FK identities.user_id -> users.id)

```bash
HOSTINGER_DB_URL="postgresql://postgres:MOTDEPASSE@localhost:5432/postgres"

psql "$HOSTINGER_DB_URL" -c "SET session_replication_role = replica;"

psql "$HOSTINGER_DB_URL" -c "\copy auth.users (
  instance_id, id, aud, role, email, encrypted_password,
  email_confirmed_at, invited_at, confirmation_token,
  confirmation_sent_at, recovery_token, recovery_sent_at,
  email_change_token_new, email_change, email_change_sent_at,
  last_sign_in_at, raw_app_meta_data, raw_user_meta_data,
  is_super_admin, created_at, updated_at, phone,
  phone_confirmed_at, phone_change, phone_change_token,
  phone_change_sent_at, email_change_token_current,
  email_change_confirm_status, banned_until,
  reauthentication_token, reauthentication_sent_at,
  is_sso_user, deleted_at, is_anonymous
) FROM 'auth_users.csv' WITH CSV HEADER"

psql "$HOSTINGER_DB_URL" -c "\copy auth.identities (
  provider_id, user_id, identity_data, provider,
  last_sign_in_at, created_at, updated_at, id
) FROM 'auth_identities.csv' WITH CSV HEADER"

psql "$HOSTINGER_DB_URL" -c "SET session_replication_role = DEFAULT;"
```

Note : les colonnes générées (`auth.users.confirmed_at`,
`auth.identities.email`) sont volontairement absentes des deux -- elles se
recalculent automatiquement à l'insertion, Postgres refuse qu'on leur
donne une valeur explicite.

## Vérification

Tester une vraie connexion agent sur l'app pointée vers cette instance
(login avec un compte SIS existant, même mot de passe qu'avant). Si ça
échoue, comparer la version de GoTrue entre Tibus 1.0 (Supabase Cloud,
gérée automatiquement) et la stack self-hosted -- un écart de version
peut introduire des colonnes/contraintes différentes.
EOF

echo
echo "Terminé. $OUT_DIR/ contient auth_users.csv, auth_identities.csv et"
echo "IMPORT_INSTRUCTIONS.md -- à transmettre au technicien par un canal sûr,"
echo "PAS par email en clair. Supprime ce dossier localement une fois le"
echo "transfert confirmé (rm -rf $OUT_DIR)."
