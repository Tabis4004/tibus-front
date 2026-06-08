# Manuel didactique Tibus — Owner

Support de **formation Owner uniquement** (gérant de compagnie). 22 menus, captures réelles, flux de mise en route.

## Fichier principal

**`Manuel_Didactique_Tibus_Owner.docx`** — à ouvrir dans Word ou Pages.

Contenu :
- Introduction et navigation Owner
- **22 fiches pédagogiques** (objectif, URL, capture réelle, procédure)
- Mise en route compagnie, pilotage quotidien, cycle billet, glossaire

Compte de démonstration pour les captures : **tabiscompany@gmail.com** · Tibus Démo Transport.

## Captures Owner (`captures/owner-real-*.png`)

21 captures réelles + `owner-real-scan.png` si disponible.

## Régénérer

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
