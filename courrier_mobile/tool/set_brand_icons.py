#!/usr/bin/env python3
"""Génère toutes les icônes de plateforme à partir d'un seul logo.

    python3 tool/set_brand_icons.py chemin/vers/logo.png [--bg "#FFFFFF"] [--pad 0.12]

Un même code source sert plusieurs sociétés, chacune déployée sur son propre
domaine avec sa propre marque. Les icônes étant compilées dans le build, elles
ne peuvent pas être choisies à l'exécution : ce script permet de rebrander un
build sans toucher au code, en une commande.

Ce qui est produit :
  web/favicon.png                              32
  web/icons/Icon-{192,512}.png                 icônes PWA
  web/icons/Icon-maskable-{192,512}.png        variantes masquables
  android/.../mipmap-*/ic_launcher.png         5 densités
  android/.../mipmap-*/ic_launcher_foreground  icône adaptative
  ios/.../AppIcon.appiconset/*.png             les 15 tailles du Contents.json
  windows/runner/resources/app_icon.ico        16/32/48/256

Le logo source est recadré automatiquement sur son contenu (les marges blanches
d'un fichier fourni par un client sont presque toujours généreuses et
décentreraient l'icône), puis recentré sur un carré.

iOS refuse toute transparence sur les icônes : le fond est donc aplati.
Android et le web l'acceptent, mais un fond plein reste préférable — une icône
transparente devient illisible sur un fond d'écran clair.
"""

import argparse
import json
import pathlib
import sys

try:
    from PIL import Image
except ImportError:
    sys.exit("Pillow requis :  pip3 install pillow")

ANDROID_LAUNCHER = {'mdpi': 48, 'hdpi': 72, 'xhdpi': 96, 'xxhdpi': 144, 'xxxhdpi': 192}
ANDROID_ADAPTIVE = {'mdpi': 108, 'hdpi': 162, 'xhdpi': 216, 'xxhdpi': 324, 'xxxhdpi': 432}
WEB_SIZES = (192, 512)
ICO_SIZES = (16, 32, 48, 256)


def parse_color(value: str) -> tuple:
    v = value.strip().lstrip('#')
    if len(v) == 3:
        v = ''.join(c * 2 for c in v)
    if len(v) != 6:
        sys.exit(f"Couleur invalide : {value}")
    return tuple(int(v[i:i + 2], 16) for i in (0, 2, 4)) + (255,)


def autocrop(im: Image.Image, tolerance: int = 26) -> Image.Image:
    """Retire les marges autour du logo.

    La couleur de fond est déduite des quatre coins plutôt que du paramètre
    --bg : un JPEG fourni par un client a rarement un fond blanc pur (dégradé,
    vignettage, artefacts de compression), et comparer au blanc théorique ne
    couperait rien.

    Une ligne est considérée comme marge si au moins 99,5 % de ses pixels sont
    proches du fond — le demi-pour-cent de tolérance absorbe le bruit JPEG et
    les pixels parasites isolés.
    """
    rgba = im.convert('RGBA')
    w, h = rgba.size
    px = rgba.load()

    corners = [px[0, 0], px[w - 1, 0], px[0, h - 1], px[w - 1, h - 1]]
    ref = tuple(sorted(c[i] for c in corners)[len(corners) // 2] for i in range(3))

    def is_bg(x, y):
        r, g, b, a = px[x, y]
        if a < 8:
            return True
        return (abs(r - ref[0]) <= tolerance
                and abs(g - ref[1]) <= tolerance
                and abs(b - ref[2]) <= tolerance)

    def col_is_margin(x):
        bad = sum(0 if is_bg(x, y) else 1 for y in range(0, h, 2))
        return bad <= max(1, (h // 2) * 5 // 1000)

    def row_is_margin(y):
        bad = sum(0 if is_bg(x, y) else 1 for x in range(0, w, 2))
        return bad <= max(1, (w // 2) * 5 // 1000)

    left, right, top, bottom = 0, w - 1, 0, h - 1
    while left < right and col_is_margin(left):
        left += 1
    while right > left and col_is_margin(right):
        right -= 1
    while top < bottom and row_is_margin(top):
        top += 1
    while bottom > top and row_is_margin(bottom):
        bottom -= 1
    return rgba.crop((left, top, right + 1, bottom + 1))


def square(logo: Image.Image, size: int, bg: tuple, pad: float,
            transparent: bool = False) -> Image.Image:
    """Logo centré sur un carré, avec marge relative."""
    canvas = Image.new('RGBA', (size, size), (0, 0, 0, 0) if transparent else bg)
    inner = max(1, int(size * (1 - 2 * pad)))
    ratio = min(inner / logo.width, inner / logo.height)
    resized = logo.resize(
        (max(1, round(logo.width * ratio)), max(1, round(logo.height * ratio))),
        Image.LANCZOS,
    )
    canvas.paste(resized,
                 ((size - resized.width) // 2, (size - resized.height) // 2),
                 resized)
    return canvas


def flatten(im: Image.Image, bg: tuple) -> Image.Image:
    """Aplatit sur le fond — exigé par iOS, souhaitable ailleurs."""
    out = Image.new('RGB', im.size, bg[:3])
    out.paste(im, (0, 0), im)
    return out


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument('logo')
    ap.add_argument('--bg', default='#FFFFFF', help="couleur de fond (défaut blanc)")
    ap.add_argument('--pad', type=float, default=0.12,
                    help="marge autour du logo, 0.12 = 12 %% de chaque côté")
    ap.add_argument('--no-crop', action='store_true',
                    help="ne pas recadrer automatiquement le logo source")
    ap.add_argument('--tolerance', type=int, default=26,
                    help="tolérance de détection du fond lors du recadrage")
    args = ap.parse_args()

    root = pathlib.Path(__file__).resolve().parent.parent
    bg = parse_color(args.bg)

    src = Image.open(args.logo)
    logo = src.convert('RGBA') if args.no_crop else autocrop(src, args.tolerance)
    print(f"logo source {src.size} -> contenu utile {logo.size}")

    def write(im: Image.Image, path: pathlib.Path, rgb: bool = True) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        (flatten(im, bg) if rgb else im).save(path)
        print(f"  {path.relative_to(root)}")

    # ---------------------------------------------------------------- Web
    print("web")
    # Ces noms précis sont ceux référencés par web/index.html : générer
    # seulement favicon.png ne changerait rien à ce qu'affiche l'onglet.
    write(square(logo, 32, bg, args.pad), root / 'web/favicon.png')
    for s_ in (16, 32, 48):
        write(square(logo, s_, bg, args.pad), root / f'web/favicon-{s_}x{s_}.png')
    write(square(logo, 180, bg, args.pad), root / 'web/apple-touch-icon.png')
    ico_web = root / 'web/favicon.ico'
    flatten(square(logo, 256, bg, args.pad), bg).save(
        ico_web, sizes=[(x, x) for x in (16, 32, 48)])
    print(f"  {ico_web.relative_to(root)}  (16x16, 32x32, 48x48)")
    for s in WEB_SIZES:
        write(square(logo, s, bg, args.pad), root / f'web/icons/Icon-{s}.png')
        # Maskable : marge plus large, le lanceur rogne jusqu'à 20 % du bord.
        write(square(logo, s, bg, max(args.pad, 0.22)),
              root / f'web/icons/Icon-maskable-{s}.png')

    # ------------------------------------------------------------ Android
    print("android")
    res = root / 'android/app/src/main/res'
    for d, s in ANDROID_LAUNCHER.items():
        write(square(logo, s, bg, args.pad), res / f'mipmap-{d}/ic_launcher.png')
    # Le premier plan adaptatif n'est produit que si le projet déclare une
    # icône adaptative (mipmap-anydpi-v26). Sinon Android ignore ces fichiers
    # et ils ne feraient qu'alourdir l'APK.
    if (res / 'mipmap-anydpi-v26/ic_launcher.xml').exists():
        for d, s in ANDROID_ADAPTIVE.items():
            write(square(logo, s, bg, 0.30, transparent=True),
                  res / f'mipmap-{d}/ic_launcher_foreground.png', rgb=False)
    else:
        print("  (pas d'icône adaptative déclarée — premier plan non généré)")

    # ---------------------------------------------------------------- iOS
    appicon = root / 'ios/Runner/Assets.xcassets/AppIcon.appiconset'
    contents = appicon / 'Contents.json'
    if contents.exists():
        print("ios")
        wanted = {}
        for entry in json.loads(contents.read_text())['images']:
            name = entry.get('filename')
            if not name:
                continue
            base = float(entry['size'].split('x')[0])
            scale = int(entry['scale'].rstrip('x'))
            wanted[name] = round(base * scale)
        for name, s in sorted(wanted.items(), key=lambda kv: kv[1]):
            write(square(logo, s, bg, args.pad), appicon / name)
    else:
        print("ios : Contents.json absent, ignoré")

    # ------------------------------------------------------------ Windows
    ico = root / 'windows/runner/resources/app_icon.ico'
    if ico.parent.exists():
        print("windows")
        base = flatten(square(logo, 256, bg, args.pad), bg)
        ico.parent.mkdir(parents=True, exist_ok=True)
        base.save(ico, sizes=[(s, s) for s in ICO_SIZES])
        print(f"  {ico.relative_to(root)}  ({', '.join(f'{s}x{s}' for s in ICO_SIZES)})")
    else:
        print("windows : dossier absent, ignoré")

    print("\nTerminé. Pense à `flutter clean` avant de rebuilder : Gradle et "
          "Xcode mettent les ressources en cache.")


if __name__ == '__main__':
    main()
