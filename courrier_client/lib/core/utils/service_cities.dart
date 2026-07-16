import 'dart:math';

/// Zones de service Tibus Ride — copie fidèle de CITIES côté web
/// (tibusride-front/src/lib/pricing.ts) : centre de chaque ville de service +
/// pays associé. Nécessaire pour résoudre `rides.country` à la création
/// d'une livraison (voir countryForCoords ci-dessous) — ce champ est utilisé
/// par le calcul de commission (compute_ride_commission()) et la
/// tarification par pays (delivery_pricing_settings.country), donc une
/// livraison créée sans lui applique la mauvaise grille tarifaire, voire
/// échoue à l'insertion si la colonne est NOT NULL côté base.
class ServiceZone {
  final String city;
  final String country;
  final String countryCode;
  final double lat;
  final double lng;

  const ServiceZone({
    required this.city,
    required this.country,
    required this.countryCode,
    required this.lat,
    required this.lng,
  });
}

const List<ServiceZone> kServiceCities = [
  ServiceZone(city: 'Dakar', country: 'Sénégal', countryCode: 'SN', lat: 14.7167, lng: -17.4677),
  ServiceZone(city: 'Abidjan', country: "Côte d'Ivoire", countryCode: 'CI', lat: 5.3600, lng: -4.0083),
  ServiceZone(city: 'Lomé', country: 'Togo', countryCode: 'TG', lat: 6.1319, lng: 1.2228),
  ServiceZone(city: 'Cotonou', country: 'Bénin', countryCode: 'BJ', lat: 6.3703, lng: 2.3912),
  ServiceZone(city: 'Niamey', country: 'Niger', countryCode: 'NE', lat: 13.5117, lng: 2.1251),
  ServiceZone(city: 'Bamako', country: 'Mali', countryCode: 'ML', lat: 12.6392, lng: -8.0029),
  ServiceZone(city: 'Ouagadougou', country: 'Burkina Faso', countryCode: 'BF', lat: 12.3714, lng: -1.5197),
  ServiceZone(city: 'Accra', country: 'Ghana', countryCode: 'GH', lat: 5.6037, lng: -0.1870),
  ServiceZone(city: 'Lagos', country: 'Nigeria', countryCode: 'NG', lat: 6.5244, lng: 3.3792),
  ServiceZone(city: 'Abuja', country: 'Nigeria', countryCode: 'NG', lat: 9.0579, lng: 7.4951),
  ServiceZone(city: 'Conakry', country: 'Guinée', countryCode: 'GN', lat: 9.6412, lng: -13.5784),
];

double _haversineKm(double lat1, double lng1, double lat2, double lng2) {
  const r = 6371.0;
  double rad(double deg) => deg * pi / 180;
  final dLat = rad(lat2 - lat1);
  final dLng = rad(lng2 - lng1);
  final a = sin(dLat / 2) * sin(dLat / 2) + cos(rad(lat1)) * cos(rad(lat2)) * sin(dLng / 2) * sin(dLng / 2);
  return 2 * r * asin(sqrt(a));
}

/// Ville de service la plus proche d'un point GPS — même logique que
/// nearestServiceCity() côté web (recherche globale, pas de rayon strict).
ServiceZone nearestServiceCity(double lat, double lng) {
  var best = kServiceCities.first;
  var bestKm = double.infinity;
  for (final zone in kServiceCities) {
    final d = _haversineKm(zone.lat, zone.lng, lat, lng);
    if (d < bestKm) {
      bestKm = d;
      best = zone;
    }
  }
  return best;
}

/// Pays résolu depuis un point GPS réel — même contrat que countryForCoords()
/// côté web (tibusride-front/src/lib/pricing.ts) : uniquement basé sur la
/// position de départ, jamais sur le profil utilisateur.
String countryForCoords(double lat, double lng) => nearestServiceCity(lat, lng).country;
