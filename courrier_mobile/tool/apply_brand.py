#!/usr/bin/env python3
"""Applique la marque d'un client à l'ensemble du projet.

    python3 tool/apply_brand.py sis
    python3 tool/apply_brand.py default        # revient à Tibus

Un seul code source sert plusieurs sociétés, chacune sur son domaine. Icônes,
titres et couleurs sont compilés dans le build : ils ne peuvent pas être
choisis à l'exécution. Ce script les remplace tous depuis
`branding/<client>/brand.json`, en une commande, de façon idempotente.

Ce qui est modifié :
  web/index.html            <title>, description, apple-mobile-web-app-title
  web/manifest.json         name, short_name, description, couleurs
  android/…/AndroidManifest android:label
  ios/Runner/Info.plist     CFBundleDisplayName, CFBundleName
  windows/runner/Runner.rc  ProductName, FileDescription, CompanyName
  toutes les icônes         via tool/set_brand_icons.py

La marque appliquée est mémorisée dans `branding/.current`, pour qu'un
`git status` inattendu s'explique d'un coup d'œil.
"""

import json
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
BRANDING = ROOT / 'branding'


def fail(msg: str) -> None:
    sys.exit(f"apply_brand: {msg}")


def load_brand(name: str) -> dict:
    path = BRANDING / name / 'brand.json'
    if not path.exists():
        available = sorted(p.name for p in BRANDING.iterdir()
                           if p.is_dir() and (p / 'brand.json').exists())
        fail(f"{path.relative_to(ROOT)} introuvable. Marques disponibles : "
             f"{', '.join(available) or 'aucune'}")
    brand = json.loads(path.read_text(encoding='utf-8'))
    for key in ('appName', 'shortName', 'description'):
        if not brand.get(key):
            fail(f"champ « {key} » manquant dans {path.relative_to(ROOT)}")
    return brand


def patch(path: pathlib.Path, rules: list[tuple[str, str]]) -> None:
    """Applique des substitutions regex, en signalant celles qui ne matchent pas.

    Un motif qui ne trouve rien est une erreur, pas un détail : cela veut dire
    que le fichier a changé de forme et qu'une partie de la marque resterait
    celle du client précédent — le genre de bug qu'on ne voit qu'en production.
    """
    if not path.exists():
        print(f"  (absent, ignoré) {path.relative_to(ROOT)}")
        return
    text = original = path.read_text(encoding='utf-8')
    missed = []
    for pattern, replacement in rules:
        text, n = re.subn(pattern, replacement, text, count=1, flags=re.S)
        if n == 0:
            missed.append(pattern)
    if missed:
        print(f"  ATTENTION {path.relative_to(ROOT)} : "
              f"{len(missed)} motif(s) non trouvé(s)")
        for m in missed:
            print(f"      {m}")
    if text != original:
        path.write_text(text, encoding='utf-8')
        print(f"  {path.relative_to(ROOT)}")
    else:
        print(f"  (déjà à jour) {path.relative_to(ROOT)}")


def main() -> None:
    if len(sys.argv) != 2:
        fail("usage : apply_brand.py <client>")
    name = sys.argv[1]
    brand = load_brand(name)

    app = brand['appName']
    short = brand['shortName']
    desc = brand['description']
    theme = brand.get('themeColor', '#16507A')
    background = brand.get('backgroundColor', '#FFFFFF')
    company = brand.get('companyId', 'com.tibus')

    def esc(v: str) -> str:
        """Protège les antislashs et références de groupe dans un remplacement."""
        return v.replace('\\', r'\\')

    print(f"Marque « {name} » -> {app}")

    print("web/index.html")
    patch(ROOT / 'web/index.html', [
        (r'(<meta name="description" content=")[^"]*(")', rf'\1{esc(desc)}\2'),
        (r'(<meta name="apple-mobile-web-app-title" content=")[^"]*(")',
         rf'\1{esc(short)}\2'),
        (r'(<title>)[^<]*(</title>)', rf'\1{esc(app)}\2'),
    ])

    print("web/manifest.json")
    manifest_path = ROOT / 'web/manifest.json'
    if manifest_path.exists():
        manifest = json.loads(manifest_path.read_text(encoding='utf-8'))
        manifest.update({
            'name': app,
            'short_name': short,
            'description': desc,
            'theme_color': theme,
            'background_color': background,
        })
        manifest_path.write_text(
            json.dumps(manifest, indent=4, ensure_ascii=False) + '\n',
            encoding='utf-8')
        print(f"  {manifest_path.relative_to(ROOT)}")

    print("android")
    patch(ROOT / 'android/app/src/main/AndroidManifest.xml', [
        (r'(android:label=")[^"]*(")', rf'\1{esc(app)}\2'),
    ])

    print("ios")
    patch(ROOT / 'ios/Runner/Info.plist', [
        (r'(<key>CFBundleDisplayName</key>\s*<string>)[^<]*(</string>)',
         rf'\1{esc(app)}\2'),
        (r'(<key>CFBundleName</key>\s*<string>)[^<]*(</string>)',
         rf'\1{esc(short)}\2'),
    ])

    print("windows")
    patch(ROOT / 'windows/runner/Runner.rc', [
        (r'(VALUE "CompanyName", ")[^"]*(")', rf'\1{esc(company)}\2'),
        (r'(VALUE "FileDescription", ")[^"]*(")', rf'\1{esc(app)}\2'),
        (r'(VALUE "ProductName", ")[^"]*(")', rf'\1{esc(app)}\2'),
    ])

    # ------------------------------------------------------------- Icônes
    logo_name = brand.get('logo', 'logo.png')
    logo = BRANDING / name / logo_name
    if logo.exists():
        print("icônes")
        cmd = [sys.executable, str(ROOT / 'tool/set_brand_icons.py'), str(logo),
               '--bg', brand.get('iconBackground', background),
               '--pad', str(brand.get('iconPadding', 0.10))]
        result = subprocess.run(cmd, cwd=ROOT)
        if result.returncode != 0:
            fail("génération des icônes en échec")
    else:
        print(f"icônes : {logo.relative_to(ROOT)} absent, non régénérées")

    # Les scripts de build restaurent web/ depuis branding/<client>/webassets/
    # (web/ peut être régénéré par `flutter create`, qui écrase les favicons).
    # On y recopie donc ce qui vient d'être produit.
    webassets = BRANDING / name / 'webassets'
    (webassets / 'icons').mkdir(parents=True, exist_ok=True)
    copied = 0
    for rel in ('favicon.png', 'favicon.ico', 'favicon-16x16.png',
                'favicon-32x32.png', 'favicon-48x48.png', 'apple-touch-icon.png',
                'manifest.json', 'index.html',
                'icons/Icon-192.png', 'icons/Icon-512.png',
                'icons/Icon-maskable-192.png', 'icons/Icon-maskable-512.png'):
        src_file = ROOT / 'web' / rel
        if src_file.exists():
            (webassets / rel).write_bytes(src_file.read_bytes())
            copied += 1
    print(f"webassets\n  {webassets.relative_to(ROOT)} ({copied} fichiers)")

    (BRANDING / '.current').write_text(name + '\n', encoding='utf-8')
    print(f"\nMarque active : {name}")
    print("Lance `flutter clean` avant de builder : Gradle, Xcode et le build "
          "web mettent les ressources en cache.")


if __name__ == '__main__':
    main()
