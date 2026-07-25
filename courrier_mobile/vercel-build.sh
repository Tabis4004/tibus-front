#!/usr/bin/env bash
set -euo pipefail

RIDE_SUPABASE_URL="${RIDE_SUPABASE_URL:-${SUPABASE_URL:-}}"
RIDE_SUPABASE_ANON_KEY="${RIDE_SUPABASE_ANON_KEY:-${SUPABASE_ANON_KEY:-}}"

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

flutter pub get

flutter build web --release \
  --dart-define=RIDE_SUPABASE_URL="$RIDE_SUPABASE_URL" \
  --dart-define=RIDE_SUPABASE_ANON_KEY="$RIDE_SUPABASE_ANON_KEY"
