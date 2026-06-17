# Manuel didactique Tibus — Owner

Support de **formation Owner uniquement** (gérant de compagnie). 22 menus, captures réelles, flux de mise en route.

## Fichier principal

**`Manuel_Didactique_Tibus_Owner.docx`** — à ouvrir dans Word ou Pages.

Contenu :
- Introduction et navigation Owner
- **22 fiches pédagogiques** (objectif, URL, capture réelle, procédure)
- Mise en route compagnie, pilotage quotidien, cycle billet, glossaire

Compte de démonstration pour les captures : **tabiscompany@gmail.com** / `123456` · Tibus Démo Transport.

## Captures layout (`public/manuel/captures/`)

Fichiers `owner-real-*.png`, `capture-accueil.png`, `capture-guide.png`, `seller-real-dashboard.png`, `seller-real-sale-form.png`, `seller-real-receipt.png`, `admin-real-*.png`, etc.

Les résultats de scan (`scan-controle-*`, `seller-scan-*`) ne sont **pas** écrasés par le script.

```bash
cd ~/Documents/tibus-front
npm install
# Chrome système (recommandé) — pas besoin d'installer Chromium Playwright
MANUAL_CAPTURE_BASE=https://tibus.app npm run manual:capture-layouts
```

Le script utilise la navigation SPA (clics / `history.pushState`) : un `page.goto` direct vers `/fr/owner/*` redirige vers l'accueil avant hydratation Supabase.

## Régénérer le DOCX

Depuis n'importe quel dossier :

```bash
python3 ~/Documents/tibus-front/docs/manuel-tibus/generate-manual-didactique.py
```

Ou depuis la racine du projet `tibus-front` :

```bash
cd ~/Documents/tibus-front/docs/manuel-tibus
python3 generate-manual-didactique.py
```

Si `cd docs/manuel-tibus` échoue, vous n'êtes pas dans `tibus-front` — utilisez le chemin complet ci-dessus.

Dépendance : `pip install python-docx pillow`

## PDF

Word / Pages → **Fichier → Exporter en PDF**

## Anciens fichiers

- `Manuel_Didactique_Tibus_Compagnie.docx` — version multi-rôles (obsolète)
- `Manuel_Utilisation_Tibus_Compagnie.docx` / `.pptx` — version courte
