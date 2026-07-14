import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/services/tibus_backend.dart';
import '../data/services/ride_backend.dart';

/// Pas de vraie "classe service" pour tibus_backend/ride_backend (méthodes
/// statiques, pas d'état d'instance) — ces providers exposent simplement un
/// point d'accès Riverpod cohérent avec le reste de la famille Courrier.
final tibusBackendProvider = Provider((ref) => TibusBackend.client);
final rideBackendProvider = Provider((ref) => RideBackend.client);
