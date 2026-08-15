#!/usr/bin/env python3
"""Imprime les --dart-define dérivés de branding/<client>/brand.json.

    python3 tool/brand_dart_defines.py sis

Pont entre le JSON de marque et les --dart-define passés à `flutter build`
par tool/build_client.sh :
  - supabaseUrl / supabaseAnonKey : permet à UN client (ex. SIS après sa
    bascule vers Hostinger) de pointer vers une base Supabase différente
    de celle par défaut (Tibus 1.0), sans toucher au code des autres
    clients — voir supabase_service.dart, qui lit déjà ces --dart-define
    en priorité et retombe sur Tibus 1.0 en leur absence.
  - features.* : bascules de fonctionnalités par marque, voir
    lib/core/config/brand_features.dart.

Absence d'un champ dans brand.json = aucun --dart-define émis pour ce
champ = comportement par défaut inchangé (voir chaque constante
consommatrice pour sa valeur de repli). C'est volontaire : ce script ne
doit JAMAIS forcer une valeur pour un client qui n'a rien demandé.
"""

import json
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent


def main() -> None:
    if len(sys.argv) != 2:
        sys.exit("usage : brand_dart_defines.py <client>")
    name = sys.argv[1]
    path = ROOT / 'branding' / name / 'brand.json'
    if not path.exists():
        sys.exit(f"brand_dart_defines: {path.relative_to(ROOT)} introuvable")
    brand = json.loads(path.read_text(encoding='utf-8'))

    defines = []

    supabase_url = brand.get('supabaseUrl')
    if supabase_url:
        defines.append(f"SUPABASE_URL={supabase_url}")
    supabase_anon_key = brand.get('supabaseAnonKey')
    if supabase_anon_key:
        defines.append(f"SUPABASE_ANON_KEY={supabase_anon_key}")

    features = brand.get('features', {})
    if 'showLoyaltyPromoReferral' in features:
        value = 'true' if features['showLoyaltyPromoReferral'] else 'false'
        defines.append(f"SHOW_LOYALTY_PROMO_REFERRAL={value}")

    # Un token par ligne : build_client.sh les lit avec `mapfile`, robuste
    # même si une valeur contenait un espace (peu probable ici, mais une
    # clé anon JWT peut en théorie être longue et bizarre).
    for d in defines:
        print(f"--dart-define={d}")


if __name__ == '__main__':
    main()
