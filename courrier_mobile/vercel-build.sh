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

install_web_branding() {
  local icon="assets/icons/ICONE-01.png"
  local manifest="branding/webassets/manifest.json"
  if [ ! -f "$icon" ]; then
    echo "Missing web icon asset: $icon" >&2
    return 1
  fi
  mkdir -p web/icons
  cp "$icon" web/favicon.png
  cp "$icon" web/icons/Icon-192.png
  cp "$icon" web/icons/Icon-512.png
  cp "$icon" web/icons/Icon-maskable-192.png
  cp "$icon" web/icons/Icon-maskable-512.png
  if [ -f "$manifest" ]; then
    cp "$manifest" web/manifest.json
  fi
  python3 - <<'PY_BRANDING'
from pathlib import Path
path = Path('web/index.html')
if not path.exists():
    raise SystemExit(0)
text = path.read_text()
text = text.replace('<title>courrier_mobile</title>', '<title>Courrier</title>')
text = text.replace('<meta name="theme-color" content="#0175C2">', '<meta name="theme-color" content="#2E7D32">')
if 'rel="apple-touch-icon"' not in text and '<link rel="icon"' in text:
    text = text.replace(
        '<link rel="icon" type="image/png" href="favicon.png"/>',
        '<link rel="icon" type="image/png" href="favicon.png"/>\n  <link rel="apple-touch-icon" href="icons/Icon-192.png"/>'
    )
path.write_text(text)
PY_BRANDING
}


flutter config --enable-web --no-analytics
flutter doctor -v || true

if [ ! -d "web" ]; then
  flutter create . --platforms=web --project-name courrier_mobile --org com.tibus
fi

install_web_branding

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
