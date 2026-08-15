# Mes instructions — préparation de l'export SIS

Tout ce que je dois exécuter moi-même, sur mon Mac, contre Tibus 1.0.
Rien de ce dossier ne va sur le VPS du client — les scripts écrivent
directement leur résultat dans `../pour_technicien/`, qui est le seul
dossier à zipper et envoyer une fois tout généré.

## Ordre

1. **`02_table_schema_pg_dump.sh`** — nécessite `TIBUS1_DB_URL` (dashboard
   Supabase du projet Tibus 1.0 > Project Settings > Database >
   Connection string). Écrit directement
   `../pour_technicien/sis_schema_tables.sql`.

   ```bash
   TIBUS1_DB_URL="postgresql://postgres.xxxx:MOTDEPASSE@...supabase.com:5432/postgres" \
     ./02_table_schema_pg_dump.sh
   ```

2. **`01_generate_functions_and_triggers.sql`** — PAS un script à lancer
   ici. Ouvrir le SQL Editor de Tibus 1.0 (dashboard Supabase), coller le
   contenu de ce fichier, exécuter, puis copier le contenu de la colonne
   résultat `script` dans `../pour_technicien/functions_and_triggers.sql`
   (remplace le placeholder qui s'y trouve).

3. **`03_export_sis_data.sh`** — mêmes pré-requis que l'étape 1 (même
   `TIBUS1_DB_URL`). Écrit directement les `.csv` dans
   `../pour_technicien/sis_export/`.

   ```bash
   TIBUS1_DB_URL="postgresql://postgres.xxxx:MOTDEPASSE@...supabase.com:5432/postgres" \
     ./03_export_sis_data.sh
   ```

4. **`04_zip_pour_technicien.sh`** — vérifie que les 3 étapes précédentes
   sont bien faites (schéma, fonctions/triggers non vide, données), puis
   produit `paquet_technicien_sis.zip` prêt à envoyer.

   ```bash
   ./04_zip_pour_technicien.sh
   ```

## Après l'envoi

Le technicien suit `pour_technicien/INSTRUCTIONS.md` de son côté, sans
aucune interaction nécessaire avec moi sauf pour me renvoyer, une fois sa
base en ligne : son domaine + `ANON_KEY`.

Avec ces deux valeurs, dernière étape chez moi :

1. Renseigner `supabaseUrl` / `supabaseAnonKey` dans
   `courrier_mobile/branding/sis/brand.json`.
2. `./tool/build_client.sh sis deploy` et `./tool/build_client.sh sis apk`.

Et séparément (hors SQL, voir `../README.md`) : migrer `auth.users` et le
bucket Storage `colis-photos`.
