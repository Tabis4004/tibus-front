#!/usr/bin/env bash
set -euo pipefail

# Defaults = projet Supabase "Tibus 1.0" (kqudaqtydimjclwaihqr), la base de
# courrier_mobile — voir CLAUDE.md. Ne PAS mettre ici les identifiants de
# Tibus Ride (bjtklpjdsmqmzhncfflu), utilisés par courrier_client/livreur.
RIDE_SUPABASE_URL="${RIDE_SUPABASE_URL:-${SUPABASE_URL:-https://kqudaqtydimjclwaihqr.supabase.co}}"
RIDE_SUPABASE_ANON_KEY="${RIDE_SUPABASE_ANON_KEY:-${SUPABASE_ANON_KEY:-eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImtxdWRhcXR5ZGltamNsd2FpaHFyIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODA2MDY1NTMsImV4cCI6MjA5NjE4MjU1M30.7bbUqLqqTDTRG4HIUFVzJdYW0NpJZWyoneUYje2JQVI}}"

: "${RIDE_SUPABASE_URL:?Set RIDE_SUPABASE_URL or SUPABASE_URL in Vercel Environment Variables}"
: "${RIDE_SUPABASE_ANON_KEY:?Set RIDE_SUPABASE_ANON_KEY or SUPABASE_ANON_KEY in Vercel Environment Variables}"

cat > .env <<EOF
RIDE_SUPABASE_URL=${RIDE_SUPABASE_URL}
RIDE_SUPABASE_ANON_KEY=${RIDE_SUPABASE_ANON_KEY}
EOF

if [ ! -d "$HOME/flutter" ]; then
  git clone https://github.com/flutter/flutter.git -b stable --depth 1 "$HOME/flutter"
fi
export PATH="$PATH:$HOME/flutter/bin"

flutter config --enable-web --no-analytics
flutter doctor -v || true

if [ ! -d "web" ]; then
  flutter create . --platforms=web --project-name courrier_mobile --org com.tibus
fi

# Copie forcée des assets de branding par-dessus le dossier web (source de
# vérité : branding/webassets/, suivi par git — voir CLAUDE.md). Absente
# jusqu'ici : le favicon web de courrier_mobile restait celui par défaut de
# Flutter, jamais celui de la marque.
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

flutter build web --release \
  --dart-define=RIDE_SUPABASE_URL="$RIDE_SUPABASE_URL" \
  --dart-define=RIDE_SUPABASE_ANON_KEY="$RIDE_SUPABASE_ANON_KEY"
