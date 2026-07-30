# Marques clients

Un seul code source, plusieurs sociétés, chacune sur son domaine. Icônes,
titres et couleurs sont **compilés dans le build** : ils ne peuvent pas être
choisis à l'exécution, contrairement aux réglages métier qui vivent en base
(voir le panneau owner « Colis autonomes »).

## Builder pour un client

    ./tool/build_client.sh sis web      # build web
    ./tool/build_client.sh sis apk      # APK
    ./tool/build_client.sh sis aab      # bundle Play Store
    ./tool/build_client.sh sis windows

Le script applique la marque **avant** de compiler : impossible de livrer un
build avec le logo d'un autre client par distraction.

## Ajouter un client

1. `mkdir branding/<client>`
2. y déposer le logo (PNG ou JPEG, carré ou non, marges indifférentes)
3. copier `branding/default/brand.json`, ajuster les valeurs
4. `./tool/build_client.sh <client> web`

## Revenir à la marque par défaut

    python3 tool/apply_brand.py default

La marque actuellement appliquée est notée dans `branding/.current`. Les
icônes et les titres du dépôt reflètent donc le **dernier client buildé** :
c'est normal, et c'est pourquoi il faut toujours passer par
`build_client.sh` plutôt que par `flutter build` directement.
