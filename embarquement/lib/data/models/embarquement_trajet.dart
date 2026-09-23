/// Un itinéraire tel que Tibus le connaît : un segment gare → gare de
/// ProgrammationTrajetArrets, avec son prix.
///
/// C'EST la source unique des tarifs (migration 212). Le module ne tient plus
/// son propre référentiel d'itinéraires : deux tables de prix qui divergent,
/// c'est exactement le reproche que notre client fait à son prestataire
/// actuel. Les trajets et leurs tarifs se créent dans Tibus — gare (dans une
/// ville), puis itinéraire gare de départ → gare d'arrivée, puis prix —
/// Embarquement se contente de lire.
///
/// La liste est déjà filtrée par le serveur sur les gares de l'utilisateur :
/// un gérant ou un contrôleur de gare ne voit que les départs de SA gare.
class EmbarquementTrajet {
  final String fromGareId;
  final String fromGare;
  final String fromCity;
  final String toGareId;
  final String toGare;
  final String toCity;
  final num price;

  /// Vrai quand Tibus porte plusieurs tarifs contradictoires pour ce même
  /// couple de gares. L'ouverture de session est alors refusée côté serveur :
  /// mieux vaut bloquer que compter une recette sur un prix arbitraire.
  final bool priceConflict;

  const EmbarquementTrajet({
    required this.fromGareId,
    required this.fromGare,
    required this.fromCity,
    required this.toGareId,
    required this.toGare,
    required this.toCity,
    required this.price,
    required this.priceConflict,
  });

  /// Clé de sélection dans un menu déroulant — le couple de gares identifie
  /// l'itinéraire, il n'y a pas d'identifiant propre côté Tibus.
  String get key => '$fromGareId|$toGareId';

  String get label {
    final depart = fromCity.isNotEmpty && fromCity != fromGare ? '$fromGare ($fromCity)' : fromGare;
    final arrivee = toCity.isNotEmpty && toCity != toGare ? '$toGare ($toCity)' : toGare;
    return '$depart → $arrivee';
  }

  factory EmbarquementTrajet.fromMap(Map<String, dynamic> map) => EmbarquementTrajet(
        fromGareId: map['from_gare_id'] as String,
        fromGare: (map['from_gare'] ?? '') as String,
        fromCity: (map['from_city'] ?? '') as String,
        toGareId: map['to_gare_id'] as String,
        toGare: (map['to_gare'] ?? '') as String,
        toCity: (map['to_city'] ?? '') as String,
        price: (map['price'] as num?) ?? 0,
        priceConflict: (map['price_conflict'] ?? false) as bool,
      );
}
