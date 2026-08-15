# Instructions — installation de la base de données SIS

Ce paquet met en place la base de données (Postgres + authentification +
stockage fichiers) de l'application colis SIS sur votre VPS. Il ne
contient AUCUN code d'application — seulement la base de données et son
contenu actuel. L'application elle-même (le logiciel utilisé par les
agents) reste hébergée et maintenue par Tibus ; elle se connectera à
cette base une fois prête.

Tout ce dont vous avez besoin est dans ce dossier. Suivez les étapes dans
l'ordre, sur le VPS (en SSH).

## Ce qu'il vous faut avant de commencer

- Docker + Docker Compose v2 installés sur le VPS (`docker compose version`
  doit répondre).
- Un nom de domaine ou sous-domaine qui pointe déjà vers l'IP de ce VPS
  (ex. `base-sis.votredomaine.com`). Nécessaire pour le HTTPS.
- Dimensionnement minimum recommandé pour la stack complète : 2 vCPU /
  4 Go RAM. Le volume de données SIS (colis, gares, utilisateurs) est
  petit, le disque n'est pas un facteur limitant.

## Étape 1 — Installer la stack

```bash
./00_setup_supabase_stack.sh
```

Clone la stack officielle et publique de Supabase (aucun code Tibus
dedans) dans `./stack/`.

## Étape 2 — Générer les secrets

```bash
./01_configure_env.sh
```

Génère automatiquement mot de passe de base de données, clé de
chiffrement et clés d'API. **Rien à inventer ou choisir vous-même ici**,
tout est généré aléatoirement et écrit dans `stack/.env`.

## Étape 3 — 🔴 Seule valeur à renseigner vous-même : votre domaine

Ouvrez `stack/.env` et remplacez les trois lignes suivantes par votre
propre domaine (remplacez `base-sis.votredomaine.com` par le vôtre) :

```
SITE_URL=https://base-sis.votredomaine.com
API_EXTERNAL_URL=https://base-sis.votredomaine.com
SUPABASE_PUBLIC_URL=https://base-sis.votredomaine.com
```

C'est la seule modification manuelle nécessaire dans tout ce paquet.

## Étape 4 — Démarrer

```bash
cd stack
docker compose pull
docker compose up -d
docker compose ps
```

Attendez que tous les services affichent "running"/"healthy".

## Étape 5 — Reverse proxy HTTPS (exemple avec Caddy)

Si Caddy n'est pas déjà installé : `apt install caddy` (ou équivalent
selon votre distribution). Puis éditez `/etc/caddy/Caddyfile` :

```
base-sis.votredomaine.com {
    reverse_proxy localhost:8000
}
```

```bash
sudo systemctl reload caddy
```

Si vous utilisez un autre reverse proxy (Nginx, Traefik...), le principe
est le même : rediriger votre domaine en HTTPS vers `localhost:8000`.

## Étape 6 — Charger la base de données

Toujours sur le VPS, revenir dans ce dossier (pas dans `stack/`) :

```bash
cd ..
psql "postgresql://postgres:$(grep ^POSTGRES_PASSWORD= stack/.env | cut -d= -f2)@localhost:5432/postgres" \
  -f sis_schema_tables.sql
psql "postgresql://postgres:$(grep ^POSTGRES_PASSWORD= stack/.env | cut -d= -f2)@localhost:5432/postgres" \
  -f functions_and_triggers.sql
./04_import_data.sh
```

(`04_import_data.sh` vous demandera `HOSTINGER_DB_URL` si elle n'est pas
déjà positionnée — utilisez la même URL que ci-dessus.)

## Étape 7 — Informations à renvoyer à Tibus

Une fois tout démarré, transmettez UNIQUEMENT ces deux informations
(trouvées dans `stack/.env`) — rien d'autre n'est nécessaire côté Tibus :

- Votre domaine (celui de l'étape 3), ex. `https://base-sis.votredomaine.com`
- La valeur de `ANON_KEY` dans `stack/.env`

**Ne transmettez PAS** `SERVICE_ROLE_KEY` ni `POSTGRES_PASSWORD` — ce sont
des accès complets à la base, à garder strictement de votre côté.

Tibus se charge ensuite de reconfigurer l'application pour qu'elle
pointe vers votre base — aucune autre action requise de votre part.

## Notes avancées (optionnelles)

- **Sécurité réseau** : n'exposez jamais le port Postgres (5432)
  directement à Internet. Gardez-le accessible seulement en local sur le
  VPS (comme utilisé ci-dessus) ou via un tunnel SSH pour toute
  administration à distance.
- **Service `analytics` (Logflare)** : la stack le démarre par défaut ;
  il est inutile pour cet usage et un peu gourmand en ressources. Le
  désactiver est optionnel (gain de ressources, pas un correctif requis) :
  commenter le service `analytics` et ses lignes `depends_on: analytics`
  dans `stack/docker-compose.yml`, dans les services `kong`, `auth`,
  `rest`, `realtime`, `storage`, `functions`.
