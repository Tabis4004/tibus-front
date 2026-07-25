#!/usr/bin/env bash
set -euo pipefail

# NB : ce projet (courrier_mobile) initialise Supabase directement en dur
# dans lib/main.dart (projet "courrier", kqudaqtydimjclwaihqr) — pas besoin
# de fichier .env ni de --dart-define ici. Les anciennes variables
# RIDE_SUPABASE_* (copiées par erreur depuis l'app VTC courrier_livreur/
# courrier_client) ont été retirées : elles ne servaient à rien pour cette
# app et ne faisaient qu'entretenir la confusion dans les logs de build.

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

flutter build web --release