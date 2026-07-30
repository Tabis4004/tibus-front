# Marques clients

Un seul code source, plusieurs sociétés, chacune sur son domaine. Icônes,
titres et couleurs sont **compilés dans le build** : ils ne peuvent pas être
choisis à l'exécution, contrairement aux réglages métier qui vivent en base
(voir le panneau owner « Colis autonomes »).

## L'architecture, en une phrase

**Un build = une marque = un Worker.**

C'est la conséquence directe du fait que le favicon, le `<title>` et le nom de
l'application sont figés à la compilation. Deux domaines servis par un même
Worker partagent forcément une marque. Il faut donc un Worker Cloudflare par
client, tous construits depuis ce même dépôt, chacun avec sa variable `BRAND`.

    branding/default/   Tibus Courrier      Worker courrier-agent
    branding/sis/       SIS Courrier        Worker courrier-sis
    branding/<client>/  …                   Worker courrier-<client>

`default` est la marque du dépôt : c'est elle qui sort si aucune variable
`BRAND` n'est définie. Ce défaut est volontaire — ta propre marque est le cas
sûr, chaque client s'y ajoute explicitement. Un Worker mal configuré affiche
Tibus, jamais le logo d'un autre client.

## Ajouter un client

    ./tool/new_client.sh <client> <chemin/du/logo> \
        --nom "Nom Courrier" \
        --societe "Nom de la société" \
        --domaine courrier.exemple.com \
        --couleur "#1E5A9C"

Le script crée `branding/<client>/` (brand.json, logo, webassets générés) et
`wrangler.<client>.jsonc`, puis **remet la marque du dépôt à `default`** — les
icônes Android et iOS étant versionnées, laisser le dépôt branché sur un client
ferait sortir son logo sur tous les autres builds.

Commite, pousse, puis dans Cloudflare, **une seule fois par client** :

1. **Workers & Pages → Create application → Workers → Import a repository**

   | Champ | Valeur |
   |---|---|
   | Dépôt | `Tabis4004/tibus-front` |
   | Nom du Worker | `courrier-<client>` |
   | Root directory | `courrier_mobile` |
   | Build command | `./vercel-build.sh` |
   | Deploy command | `npx wrangler deploy -c wrangler.<client>.jsonc` |

   La *deploy command* est indispensable : sans `-c`, wrangler prend
   `wrangler.jsonc`, dont le champ `name` vaut `courrier-agent`. Le build du
   client serait publié par-dessus le site agent de Tibus.

2. **Settings → Variables and Secrets → Add**

       BRAND = <client>

   C'est ce qui sélectionne `branding/<client>/webassets/` dans
   `vercel-build.sh`. Sans elle, le build sort en marque Tibus.

3. **Settings → Domains & Routes → Add → Custom domain**

   Le domaine du client. Cloudflare crée le CNAME et le certificat.

## Builder

    ./tool/build_client.sh sis web       # build web local
    ./tool/build_client.sh sis deploy    # build web + wrangler deploy
    ./tool/build_client.sh sis apk       # APK
    ./tool/build_client.sh sis aab       # bundle Play Store
    ./tool/build_client.sh sis windows   # nécessite Visual Studio

Le script applique la marque **avant** de compiler : impossible de livrer un
build portant le logo d'un autre client par distraction.

Depuis un Mac, Windows est impossible (Flutter exige la toolchain Visual
Studio) : **GitHub → Actions → Build Courrier Mobile Windows**, saisir le nom
du client. Le workflow vérifie que `branding/<client>/brand.json` existe avant
de compiler, génère le dossier `windows/` (non versionné), applique la marque,
puis produit deux artefacts — le zip portable et l'installateur Inno Setup.

## Revenir à la marque par défaut

    python3 tool/apply_brand.py default

La marque appliquée localement est notée dans `branding/.current`. Ce fichier
n'a d'effet que sur les builds **locaux** : en CI, `BRAND` a la priorité.

## Deux pièges déjà rencontrés

**Le déploiement web n'est pas le rebranding.** `apply_brand.py` modifie les
sources ; le site en ligne ne change qu'après un build et un déploiement.
Aucun hard refresh ne rattrape un build absent.

**Un Worker peut porter plusieurs routes.** Vérifie dans *Domains & Routes*
qu'un Worker client ne sert que le domaine de ce client. `courrier-agent` a
servi `courrier.societe-sis.com` en plus du domaine Tibus : les deux sites ne
pouvaient alors pas avoir de marques différentes.

## Migrer un client déjà servi par `courrier-agent`

Cas de SIS, dont le domaine est encore une route de `courrier-agent`.

1. Créer le Worker `courrier-sis` (étapes 1 et 2 ci-dessus), le laisser se
   déployer, vérifier sur `courrier-sis.<sous-domaine>.workers.dev` que la
   marque servie est bien celle de SIS.
2. **courrier-agent → Domains & Routes** : retirer `courrier.societe-sis.com`.
3. **courrier-sis → Domains & Routes** : ajouter `courrier.societe-sis.com`.
4. **courrier-agent → Variables** : supprimer `BRAND` s'il y est resté, pour
   que le site agent Tibus reprenne sa propre marque au prochain build.

Faire 2 avant 3 : Cloudflare refuse qu'un même domaine soit attaché à deux
Workers. L'ordre inverse coupe le site quelques minutes.
