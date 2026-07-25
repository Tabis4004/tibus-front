#!/usr/bin/env bash
# Build web (Vercel) pour Courrier Livreur (driver moto/voiture) — voir
# vercel.json (buildCommand). Même schéma que courrier_mobile/courrier_client
# (vercel-build.sh) : le SDK Flutter n'est pas préinstallé sur Vercel, ce
# script l'installe à chaque build (pas de buildpack Flutter natif Vercel).
set -euo pipefail

# .env est gitignored (secrets) donc absent du clone Vercel, alors que
# pubspec.yaml le déclare en asset (flutter_dotenv) — on le régénère depuis
# les variables d'environnement du projet Vercel. Valeurs par défaut =
# celles déjà présentes dans .env.example (clé anon publique du projet
# Supabase Tibus Ride, sans risque à exposer côté client — anon key + RLS).
cat > .env <<EOF
RIDE_SUPABASE_URL=${RIDE_SUPABASE_URL:-https://bjtklpjdsmqmzhncfflu.supabase.co}
RIDE_SUPABASE_ANON_KEY=${RIDE_SUPABASE_ANON_KEY:-eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJqdGtscGpkc21xbXpobmNmZmx1Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODE4OTM0ODIsImV4cCI6MjA5NzQ2OTQ4Mn0.j5m-MZV5PDeknP0g3i06UjDpfpxTFbhndMauVYGmLvQ}
EOF

if [ ! -d "$HOME/flutter" ]; then
  git clone https://github.com/flutter/flutter.git -b stable --depth 1 "$HOME/flutter"
fi
export PATH="$PATH:$HOME/flutter/bin"

flutter config --enable-web --no-analytics
flutter doctor -v || true

# web/ est gitignored (régénérable, comme android/ios/macos/linux/windows) :
# on le reconstitue avant le build. Non destructif pour lib/ existant.
# 1. Génération de l'environnement web par Flutter
#!/bin/bash
set -e

if [ ! -d "$HOME/flutter" ]; then
  git clone https://github.com/flutter/flutter.git -b stable --depth 1 "$HOME/flutter"
fi
export PATH="$PATH:$HOME/flutter/bin"

flutter config --enable-web --no-analytics
flutter doctor -v || true

# Génération propre sans écraser si web existe déjà
if [ ! -d "web" ]; then
  flutter create . --platforms=web --project-name courrier_livreur --org com.tibus --template app
fi

# Copie forcée des assets de branding par-dessus le dossier web
if [ -d "branding/webassets" ]; then
  mkdir -p web/icons
  cp -f branding/webassets/favicon.png web/favicon.png 2>/dev/null || true
  cp -f branding/webassets/favicon.svg web/favicon.svg 2>/dev/null || true
  cp -f branding/webassets/manifest.json web/manifest.json 2>/dev/null || true
  cp -f branding/webassets/favicon.png web/icons/Icon-192.png 2>/dev/null || true
  cp -f branding/webassets/favicon.png web/icons/Icon-512.png 2>/dev/null || true
  cp -f branding/webassets/favicon.png web/icons/Icon-maskable-192.png 2>/dev/null || true
  cp -f branding/webassets/favicon.png web/icons/Icon-maskable-512.png 2>/dev/null || true
  python3 - <<'PY_BRANDING'
from pathlib import Path
path = Path('web/index.html')
if path.exists():
    text = path.read_text()
    text = text.replace('<title>courrier_livreur</title>', '<title>Tibus Livraison</title>')
    text = text.replace('<title>courrier livreur</title>', '<title>Tibus Livraison</title>')
    text = text.replace('href="favicon.png"', 'href="favicon.png?v=tibus-livraison-v2"')
    text = text.replace('href="manifest.json"', 'href="manifest.json?v=tibus-livraison-v2"')
    text = text.replace('href="icons/Icon-192.png"', 'href="icons/Icon-192.png?v=tibus-livraison-v2"')
    if 'rel="apple-touch-icon"' not in text and '<link rel="icon"' in text:
        text = text.replace(
            '<link rel="icon" type="image/png" href="favicon.png?v=tibus-livraison-v2"/>',
            '<link rel="icon" type="image/png" href="favicon.png?v=tibus-livraison-v2"/>\n  <link rel="apple-touch-icon" href="icons/Icon-192.png?v=tibus-livraison-v2"/>'
        )
    path.write_text(text)
PY_BRANDING
fi

flutter pub get
flutter build web --release 