#!/bin/bash
set -euo pipefail

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

if [ ! -d "web" ]; then
  flutter create . --platforms=web --project-name courrier_client
fi

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