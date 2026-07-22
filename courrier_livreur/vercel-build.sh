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
flutter create . --platforms=web --project-name courrier_livreur

# `flutter create` écrase favicon/manifest par les défauts Flutter à chaque
# build : on réapplique par-dessus le branding Tibus (seule copie versionnée,
# web/ n'étant pas commité — voir branding/webassets/).
cp branding/webassets/favicon.svg web/favicon.svg
cp branding/webassets/favicon.png web/favicon.png
cp branding/webassets/manifest.json web/manifest.json

flutter pub get
flutter build web --release
