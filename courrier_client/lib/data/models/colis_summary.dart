/// Statuts du cycle de vie d'un colis — identique à courrier_mobile
/// (colis_autonome_statut côté base Tibus principal).
enum ColisStatut { enregistre, charge, arrive, livre }

extension ColisStatutX on ColisStatut {
  static ColisStatut fromDb(String value) {
    switch (value) {
      case 'charge':
        return ColisStatut.charge;
      case 'arrive':
        return ColisStatut.arrive;
      case 'livre':
        return ColisStatut.livre;
      case 'enregistre':
      default:
        return ColisStatut.enregistre;
    }
  }

  String get label => switch (this) {
        ColisStatut.enregistre => 'Enregistré',
        ColisStatut.charge => 'Chargé',
        ColisStatut.arrive => 'Arrivé',
        ColisStatut.livre => 'Livré',
      };
}

/// Résumé du colis affiché côté client — sous-ensemble du modèle complet
/// de courrier_mobile, juste ce qui sert au suivi + à préremplir la
/// commande VTC (gare d'arrivée comme point de départ suggéré).
class ColisSummary {
  final String id;
  final ColisStatut statut;
  final String nomDestinataire;
  final String telephoneDestinataire;
  final String gareDepart;
  final String gareDestination;
  final double? montantFret;

  const ColisSummary({
    required this.id,
    required this.statut,
    required this.nomDestinataire,
    required this.telephoneDestinataire,
    required this.gareDepart,
    required this.gareDestination,
    this.montantFret,
  });

  factory ColisSummary.fromMap(Map<String, dynamic> map) => ColisSummary(
        id: map['id'] as String,
        statut: ColisStatutX.fromDb(map['statutColis'] as String? ?? 'enregistre'),
        nomDestinataire: map['nomDestinataire'] as String? ?? '',
        telephoneDestinataire: map['telephoneDestinataire'] as String? ?? '',
        gareDepart: map['gareDepart'] as String? ?? '',
        gareDestination: map['gareDestination'] as String? ?? '',
        montantFret: (map['montantFret'] as num?)?.toDouble(),
      );
}
