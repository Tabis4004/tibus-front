#!/usr/bin/env bash
# Build web (Vercel) pour Courrier (agent) — voir vercel.json (buildCommand).
# Le SDK Flutter n'est pas préinstallé sur Vercel : ce script l'installe à
# chaque build (pas de buildpack Flutter natif côté Vercel).
set -euo pipefail

# .env est gitignored (secrets) donc absent du clone Vercel, alors que
# pubspec.yaml le déclare en asset (flutter_dotenv) — on le régénère depuis
# les variables d'environnement du projet Vercel. Valeurs par défaut =
# celles déjà présentes dans .env.example (clé anon publique, sans risque
# à exposer côté client — c'est tout le principe de l'anon key + RLS).
cat > .env <<EOF
SUPABASE_URL=${SUPABASE_URL:-https://kqudaqtydimjclwaihqr.supabase.co}
SUPABASE_ANON_KEY=${SUPABASE_ANON_KEY:-eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImtxdWRhcXR5ZGltamNsd2FpaHFyIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODA2MDY1NTMsImV4cCI6MjA5NjE4MjU1M30.7bbUqLqqTDTRG4HIUFVzJdYW0NpJZWyoneUYje2JQVI}
EOF

if [ ! -d "$HOME/flutter" ]; then
  git clone https://github.com/flutter/flutter.git -b stable --depth 1 "$HOME/flutter"
fi
export PATH="$PATH:$HOME/flutter/bin"

flutter config --enable-web --no-analytics
flutter doctor -v || true

# web/ est gitignored (régénérable, comme ios/macos/linux/windows — voir
# README "Platform générés par flutter create . si absents") : on le
# reconstitue avant le build. Non destructif pour lib/ existant.
flutter create . --platforms=web --project-name courrier

# `flutter create` écrase favicon.png par le défaut Flutter à chaque build :
# on réapplique par-dessus le favicon Tibus (seule copie versionnée, web/
# n'étant pas commité — voir branding/webassets/).
cp branding/webassets/favicon.png web/favicon.png

flutter pub get
flutter build web --release
