#!/usr/bin/env bash
set -euo pipefail

SUPABASE_URL_VALUE="${SUPABASE_URL:-${RIDE_SUPABASE_URL:-https://kqudaqtydimjclwaihqr.supabase.co}}"
SUPABASE_ANON_KEY_VALUE="${SUPABASE_ANON_KEY:-${RIDE_SUPABASE_ANON_KEY:-}}"

cat > .env <<EOF
SUPABASE_URL=$SUPABASE_URL_VALUE
SUPABASE_ANON_KEY=$SUPABASE_ANON_KEY_VALUE
RIDE_SUPABASE_URL=$SUPABASE_URL_VALUE
RIDE_SUPABASE_ANON_KEY=$SUPABASE_ANON_KEY_VALUE
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
  --pwa-strategy=none \
  --dart-define=SUPABASE_URL="$SUPABASE_URL_VALUE" \
  --dart-define=SUPABASE_ANON_KEY="$SUPABASE_ANON_KEY_VALUE" \
  --dart-define=RIDE_SUPABASE_URL="$SUPABASE_URL_VALUE" \
  --dart-define=RIDE_SUPABASE_ANON_KEY="$SUPABASE_ANON_KEY_VALUE"

# Remove any stale Flutter PWA cache from browsers that already registered it.
cat > build/web/flutter_service_worker.js <<'EOF'
self.addEventListener('install', () => self.skipWaiting());

self.addEventListener('activate', (event) => {
  event.waitUntil((async () => {
    const keys = await caches.keys();
    await Promise.all(keys.map((key) => caches.delete(key)));
    await self.registration.unregister();
    const clients = await self.clients.matchAll({ type: 'window' });
    for (const client of clients) {
      client.navigate(client.url);
    }
  })());
});
EOF
