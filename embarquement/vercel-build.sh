#!/usr/bin/env bash
set -euo pipefail

# Build web d'Embarquement — même schéma que courrier_mobile/vercel-build.sh,
# utilisé aussi bien par Cloudflare Workers (Build command : bash
# vercel-build.sh, répertoire racine : embarquement) que par Vercel.
#
# Base : projet Supabase "Tibus 1.0" (kqudaqtydimjclwaihqr), comme
# courrier_mobile — voir CLAUDE.md. Surtout PAS les identifiants de Tibus
# Ride (bjtklpjdsmqmzhncfflu), qui appartiennent à courrier_client/livreur.
# Les noms de variables suivent lib/core/config/env.dart (SUPABASE_URL /
# SUPABASE_ANON_KEY), pas les RIDE_* de courrier_mobile.
SUPABASE_URL="${SUPABASE_URL:-https://kqudaqtydimjclwaihqr.supabase.co}"
SUPABASE_ANON_KEY="${SUPABASE_ANON_KEY:-eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImtxdWRhcXR5ZGltamNsd2FpaHFyIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODA2MDY1NTMsImV4cCI6MjA5NjE4MjU1M30.7bbUqLqqTDTRG4HIUFVzJdYW0NpJZWyoneUYje2JQVI}"

: "${SUPABASE_URL:?Definir SUPABASE_URL dans les variables du projet}"
: "${SUPABASE_ANON_KEY:?Definir SUPABASE_ANON_KEY dans les variables du projet}"

if [ ! -d "$HOME/flutter" ]; then
  git clone https://github.com/flutter/flutter.git -b stable --depth 1 "$HOME/flutter"
fi
export PATH="$PATH:$HOME/flutter/bin"

flutter config --enable-web --no-analytics
flutter doctor -v || true

# web/ est gitignoré (voir embarquement/.gitignore et la note CLAUDE.md sur
# les 3 apps Flutter) : il n'existe donc PAS sur le serveur de build et doit
# être régénéré ici, sinon `flutter build web` échoue sans rien expliquer.
if [ ! -d "web" ]; then
  flutter create . --platforms=web --project-name embarquement --org com.tibus
fi

flutter pub get

flutter build web --release \
  --dart-define=SUPABASE_URL="$SUPABASE_URL" \
  --dart-define=SUPABASE_ANON_KEY="$SUPABASE_ANON_KEY"
