# Migration SIS : Tibus 1.0 (Supabase) -> Hostinger (Supabase self-hosted)

Contexte : `courrier_mobile` (agent/guichet colis) est partagé entre Tibus
et SIS sur la même base Supabase « Tibus 1.0 »
(`kqudaqtydimjclwaihqr.supabase.co`). SIS veut héberger ses propres
données sur son VPS Hostinger, via la stack officielle Supabase
self-hosted (Docker).

## Deux dossiers, deux responsables

```
hostinger_migration/
  pour_moi/           <- ce que J'EXÉCUTE, sur mon Mac, contre Tibus 1.0
  pour_technicien/     <- ce que le TECHNICIEN SIS exécute, sur son VPS
```

Le technicien du client n'a accès qu'à sa propre base de données, jamais
au dépôt `tibus-front` ni au code source des apps (Flutter, React).

- **`pour_moi/`** — mes 3 scripts + mon `README.md`. Je les lance depuis
  mon Mac, contre Tibus 1.0 uniquement. Ils écrivent leur résultat
  directement dans `pour_technicien/`. Dernière étape : zipper
  `pour_technicien/` et l'envoyer.
- **`pour_technicien/`** — un paquet autonome : uniquement des fichiers
  `.sh`/`.sql`/`.csv`/`.md`, zéro code d'application. Son
  `INSTRUCTIONS.md` est écrit directement pour le technicien, en
  français simple, avec une seule valeur à saisir manuellement de son
  côté (son nom de domaine) — tout le reste (mots de passe, clés) est
  généré automatiquement par ses propres scripts.

Retour du technicien vers moi, une fois sa base en ligne : uniquement son
domaine + `ANON_KEY` (jamais `SERVICE_ROLE_KEY` ni le mot de passe
Postgres). Je termine ensuite moi-même, sur mon Mac : mise à jour de
`branding/sis/brand.json` puis rebuild/redéploiement via mon propre
pipeline GitHub/Cloudflare — le client n'a à aucun moment d'accès au
repo ni au déploiement.

Le dossier `docker/` de cet emplacement est obsolète (déplacé dans
`pour_technicien/`) — voir `docker/DEPRECATED.md`, à supprimer quand tu
veux.

## Marche à suivre

1. Ouvrir `pour_moi/README.md` et suivre les 4 étapes (schéma, fonctions/
   triggers, données, zip).
2. Envoyer `paquet_technicien_sis.zip` au technicien SIS.
3. Il suit `pour_technicien/INSTRUCTIONS.md` de son côté.
4. Il te renvoie domaine + `ANON_KEY`.
5. Tu termines avec `branding/sis/brand.json` + `build_client.sh sis
   deploy`/`apk` (détaillé en bas de `pour_moi/README.md`).

## Périmètre

18 tables, 85 fonctions, 8 triggers — voir l'en-tête de
`pour_moi/01_generate_functions_and_triggers.sql` pour le détail et le
raisonnement (dépendances tracées directement sur la base le 2026-08-09).
Explicitement exclus, à la demande du client : codes promo, parrainage,
fidélité voyageur — SIS est un logiciel métier interne, sans volet client
pour les réservations.

## Ce qui N'EST PAS couvert par ces scripts

Ces deux points sont hors SQL, à traiter séparément avant la bascule
définitive :

### `auth.users` (comptes de connexion, géré par GoTrue)

Les comptes agents SIS vivent dans `auth.users`, séparé de la table
publique `Users`. GoTrue étant le même logiciel des deux côtés (Tibus 1.0
et la stack self-hosted), un export/import direct des lignes concernées
devrait fonctionner sans forcer de réinitialisation de mot de passe côté
utilisateur — mais cela n'a pas encore été scripté ni testé. À faire
avant la bascule, avec un test de connexion réel sur un compte agent SIS
migré.

### Bucket Storage `colis-photos` (fichiers photo)

Les photos de colis sont des fichiers dans Supabase Storage, pas des
lignes SQL — non couvertes par pg_dump ni par les scripts CSV. Pour les
lister : `SELECT id, photo_path FROM colis_autonomes WHERE company_id =
'1422ab71-4a45-45af-8e7c-4c72a2f9b296' AND photo_path IS NOT NULL;` puis
les télécharger (dashboard ou Storage API) et les ré-uploader sur le
bucket `colis-photos` de la nouvelle instance, en conservant les mêmes
chemins (`photo_path`) pour que les liens existants restent valides.

Tant que `branding/sis/brand.json` n'a pas été mis à jour, SIS continue
de communiquer avec Tibus 1.0 — la migration peut donc être préparée et
testée sans risque de coupure.
