#!/usr/bin/env python3
"""Incrémente et renvoie le versionCode Android d'une marque.

    python3 tool/bump_version_code.py sis          # incrémente, affiche N
    python3 tool/bump_version_code.py sis --peek   # affiche le prochain N sans écrire

Chaque marque est une app Play Store distincte (applicationId différent),
donc chacune a son propre compteur : branding/<marque>/version_code (suivi
par git -- COMMITTER ce fichier après chaque envoi sur le Play Store, sinon
un autre poste repartirait d'un numéro déjà utilisé).

Play Store refuse une release dont le versionCode n'est pas supérieur à
celui déjà en production (erreur « ne permet à aucun utilisateur actuel
d'effectuer une mise à jour »), même si l'envoi de l'AAB a été accepté.

Si le fichier n'existe pas, on part du +N de pubspec.yaml.
"""
import pathlib
import re
import sys

root = pathlib.Path(__file__).resolve().parent.parent
if len(sys.argv) < 2:
    sys.exit("usage : bump_version_code.py <marque> [--peek]")
brand = sys.argv[1]
peek = "--peek" in sys.argv[2:]

brand_dir = root / "branding" / brand
if not brand_dir.is_dir():
    sys.exit(f"marque inconnue : {brand}")
counter = brand_dir / "version_code"

if counter.exists():
    current = int(counter.read_text().strip())
else:
    m = re.search(r"^version:\s*[^+\s]+\+(\d+)", (root / "pubspec.yaml").read_text(), re.M)
    current = int(m.group(1)) if m else 0

nxt = current + 1
if not peek:
    counter.write_text(f"{nxt}\n")
print(nxt)
