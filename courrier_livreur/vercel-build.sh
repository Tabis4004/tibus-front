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
# on le reconstitue avant le build si absent. Non destructif pour lib/ existant.
if [ ! -d "web" ]; then
  flutter create . --platforms=web --project-name courrier_livreur --org com.tibus --template app
fi

# Copie forcée des assets de branding par-dessus le dossier web (source de
# vérité : branding/webassets/, suivi par git — voir CLAUDE.md).
if [ -d "branding/webassets" ]; then
  mkdir -p web/icons
  cp -f branding/webassets/favicon.png web/favicon.png 2>/dev/null || true
  cp -f branding/webassets/favicon.ico web/favicon.ico 2>/dev/null || true
  cp -f branding/webassets/favicon-16x16.png web/favicon-16x16.png 2>/dev/null || true
  cp -f branding/webassets/favicon-32x32.png web/favicon-32x32.png 2>/dev/null || true
  cp -f branding/webassets/favicon-48x48.png web/favicon-48x48.png 2>/dev/null || true
  cp -f branding/webassets/apple-touch-icon.png web/apple-touch-icon.png 2>/dev/null || true
  cp -f branding/webassets/icons/Icon-192.png web/icons/Icon-192.png 2>/dev/null || true
  cp -f branding/webassets/icons/Icon-512.png web/icons/Icon-512.png 2>/dev/null || true
  cp -f branding/webassets/icons/Icon-maskable-192.png web/icons/Icon-maskable-192.png 2>/dev/null || true
  cp -f branding/webassets/icons/Icon-maskable-512.png web/icons/Icon-maskable-512.png 2>/dev/null || true
  cp -f branding/webassets/manifest.json web/manifest.json 2>/dev/null || true
  cp -f branding/webassets/index.html web/index.html 2>/dev/null || true
fi

flutter pub get
flutter build web --release
