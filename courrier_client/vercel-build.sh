#!/usr/bin/env bash
# Build web (Vercel) pour Courrier Client (expéditeur/destinataire) — voir
# vercel.json (buildCommand). Le SDK Flutter n'est pas préinstallé sur
# Vercel : ce script l'installe à chaque build.
set -euo pipefail

# .env est gitignored (secrets) donc absent du clone Vercel, alors que
# pubspec.yaml le déclare en asset (flutter_dotenv) — on le régénère depuis
# les variables d'environnement du projet Vercel. DEUX backends distincts
# (voir lib/core/config/env.dart) : Tibus principal (suivi colis, mêmes
# valeurs publiques que courrier_mobile) et Tibus Ride (livraison VTC,
# projet Supabase séparé — RIDE_SUPABASE_ANON_KEY DOIT être défini dans les
# variables d'environnement du projet Vercel, aucune valeur par défaut
# connue ici ; sans elle, seul le suivi colis fonctionnera).
cat > .env <<EOF
SUPABASE_URL=${SUPABASE_URL:-https://kqudaqtydimjclwaihqr.supabase.co}
SUPABASE_ANON_KEY=${SUPABASE_ANON_KEY:-eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImtxdWRhcXR5ZGltamNsd2FpaHFyIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODA2MDY1NTMsImV4cCI6MjA5NjE4MjU1M30.7bbUqLqqTDTRG4HIUFVzJdYW0NpJZWyoneUYje2JQVI}
RIDE_SUPABASE_URL=${RIDE_SUPABASE_URL:-https://bjtklpjdsmqmzhncfflu.supabase.co}
RIDE_SUPABASE_ANON_KEY=${RIDE_SUPABASE_ANON_KEY:-}
EOF

if [ ! -d "$HOME/flutter" ]; then
  git clone https://github.com/flutter/flutter.git -b stable --depth 1 "$HOME/flutter"
fi
export PATH="$PATH:$HOME/flutter/bin"

flutter config --enable-web --no-analytics
flutter doctor -v || true

# web/ est gitignored (régénérable, comme android/ios/macos/linux/windows —
# voir README) : on le reconstitue avant le build. Non destructif pour lib/.
flutter create . --platforms=web --project-name courrier_client

# `flutter create` écrase favicon/manifest par les défauts Flutter à chaque
# build : on réapplique par-dessus le branding Tibus (seule copie versionnée,
# web/ n'étant pas commité — voir branding/webassets/).
cp branding/webassets/favicon.svg web/favicon.svg
cp branding/webassets/favicon.png web/favicon.png
cp branding/webassets/manifest.json web/manifest.json

flutter pub get
flutter build web --release
