/// Statuts du cycle de vie d'un colis — repris à l'identique du module
/// "Colis Autonome" de Tibus (voir colis_autonome_statut côté base).
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

  String get dbValue => switch (this) {
        ColisStatut.enregistre => 'enregistre',
        ColisStatut.charge => 'charge',
        ColisStatut.arrive => 'arrive',
        ColisStatut.livre => 'livre',
      };

  String get label => switch (this) {
        ColisStatut.enregistre => 'Enregistré',
        ColisStatut.charge => 'Chargé',
        ColisStatut.arrive => 'Arrivé',
        ColisStatut.livre => 'Livré',
      };

  /// Prochain statut du cycle, null si terminal.
  ColisStatut? get next => switch (this) {
        ColisStatut.enregistre => ColisStatut.charge,
        ColisStatut.charge => ColisStatut.arrive,
        ColisStatut.arrive => ColisStatut.livre,
        ColisStatut.livre => null,
      };
}

class Colis {
  final String id;
  final ColisStatut statut;
  final String nomExpediteur;
  final String telephoneExpediteur;
  final String nomDestinataire;
  final String telephoneDestinataire;
  final String? descriptionContenu;
  final double? poidsKg;
  final int nombrePieces;
  final double montantFret;
  /// Valeur déclarée de la marchandise (XOF) — obligatoire côté base depuis
  /// la migration colis_pourcentage_percu ; sert de base au remboursement
  /// en cas de perte (voir reçu web/mobile).
  final double? valeurMarchandise;
  /// Pourcentage de la valeur marchandise utilisé pour calculer montantFret
  /// quand l'agent choisit le mode de calcul automatique.
  final double? pourcentagePercu;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String gareDepart;
  final String gareDestination;
  final List<String> natures;

  const Colis({
    required this.id,
    required this.statut,
    required this.nomExpediteur,
    required this.telephoneExpediteur,
    required this.nomDestinataire,
    required this.telephoneDestinataire,
    this.descriptionContenu,
    this.poidsKg,
    required this.nombrePieces,
    required this.montantFret,
    this.valeurMarchandise,
    this.pourcentagePercu,
    required this.createdAt,
    required this.updatedAt,
    required this.gareDepart,
    required this.gareDestination,
    required this.natures,
  });

  factory Colis.fromMap(Map<String, dynamic> map) {
    return Colis(
      id: map['id'] as String,
      statut: ColisStatutX.fromDb(map['statutColis'] as String? ?? 'enregistre'),
      nomExpediteur: map['nomExpediteur'] as String? ?? '',
      telephoneExpediteur: map['telephoneExpediteur'] as String? ?? '',
      nomDestinataire: map['nomDestinataire'] as String? ?? '',
      telephoneDestinataire: map['telephoneDestinataire'] as String? ?? '',
      descriptionContenu: map['descriptionContenu'] as String?,
      poidsKg: (map['poidsKg'] as num?)?.toDouble(),
      nombrePieces: (map['nombrePieces'] as num?)?.toInt() ?? 1,
      montantFret: (map['montantFret'] as num?)?.toDouble() ?? 0,
      valeurMarchandise: (map['valeurMarchandise'] as num?)?.toDouble(),
      pourcentagePercu: (map['pourcentagePercu'] as num?)?.toDouble(),
      createdAt: DateTime.tryParse(map['createdAt'] as String? ?? '') ?? DateTime.now(),
      updatedAt: DateTime.tryParse(map['updatedAt'] as String? ?? '') ?? DateTime.now(),
      gareDepart: map['gareDepart'] as String? ?? '',
      gareDestination: map['gareDestination'] as String? ?? '',
      natures: (map['natures'] as List?)?.map((e) => e.toString()).toList() ?? const [],
    );
  }
}

/// Gare d'une compagnie, pour les sélecteurs départ/destination — reflète
/// list_company_station_gares (même RPC que le web, voir
/// src/lib/supabase/station-cash.ts).
class GareOption {
  final String id;
  final String name;

  const GareOption({required this.id, required this.name});

  factory GareOption.fromMap(Map<String, dynamic> map) => GareOption(
        id: map['id'] as String? ?? '',
        name: map['name'] as String? ?? '',
      );
}

/// Statut d'une session de caisse — même valeurs que la colonne
/// caisses_gares.statut côté base.
enum StationCashStatus { ouverte, enReversement, cloturee, unknown }

extension StationCashStatusX on StationCashStatus {
  static StationCashStatus fromDb(String? value) {
    switch (value) {
      case 'ouverte':
        return StationCashStatus.ouverte;
      case 'en_reversement':
        return StationCashStatus.enReversement;
      case 'cloturee':
        return StationCashStatus.cloturee;
      default:
        return StationCashStatus.unknown;
    }
  }
}

/// Caisse (session gare) ouverte par l'agent connecté — reflète
/// get_open_station_cash_for_user (même RPC que le web, voir
/// src/lib/supabase/station-cash.ts). register_colis_autonome exige une
/// caisse ouverte et que la gare de départ corresponde exactement à cette
/// caisse (assert_seller_cash_departure_gare côté base) : sans caisse
/// ouverte, l'enregistrement échoue toujours, quel que soit le formulaire.
class OpenStationCash {
  final bool open;
  final bool pendingReversal;
  final String? id;
  final String? gareId;
  final String? gareName;
  final String? sessionLabel;
  final double? balance;
  final double? openingFloat;
  final String? openedAt;
  final StationCashStatus? status;

  const OpenStationCash({
    required this.open,
    this.pendingReversal = false,
    this.id,
    this.gareId,
    this.gareName,
    this.sessionLabel,
    this.balance,
    this.openingFloat,
    this.openedAt,
    this.status,
  });

  factory OpenStationCash.fromMap(Map<String, dynamic> map) => OpenStationCash(
        open: map['open'] as bool? ?? false,
        pendingReversal: map['pendingReversal'] as bool? ?? false,
        id: map['id'] as String?,
        gareId: map['gareId'] as String?,
        gareName: map['gareName'] as String?,
        sessionLabel: map['sessionLabel'] as String?,
        balance: (map['balance'] as num?)?.toDouble(),
        openingFloat: (map['openingFloat'] as num?)?.toDouble(),
        openedAt: map['openedAt'] as String?,
        status: StationCashStatusX.fromDb(map['status'] as String?),
      );
}

/// Ligne du journal de caisse — reflète list_station_cash_movements.
class StationCashMovement {
  final String id;
  final DateTime createdAt;
  final String type;
  final double amount;
  final double balanceAfter;
  final String? authorName;
  final String? note;

  const StationCashMovement({
    required this.id,
    required this.createdAt,
    required this.type,
    required this.amount,
    required this.balanceAfter,
    this.authorName,
    this.note,
  });

  factory StationCashMovement.fromMap(Map<String, dynamic> map) => StationCashMovement(
        id: map['id'] as String,
        createdAt: DateTime.tryParse(map['created_at'] as String? ?? '') ?? DateTime.now(),
        type: map['type_mouvement'] as String? ?? '',
        amount: (map['montant'] as num?)?.toDouble() ?? 0,
        balanceAfter: (map['solde_apres'] as num?)?.toDouble() ?? 0,
        authorName: map['effectue_par_name'] as String?,
        note: map['note'] as String?,
      );

  /// Libellé lisible du type de mouvement — même mapping que
  /// STATION_CASH_MOVEMENT_LABELS côté web.
  String get typeLabel => switch (type) {
        'encaissement_billet' => 'Encaissement guichet',
        'encaissement_colis' => 'Encaissement guichet',
        'decaissement_annulation' => 'Décaissement annulation',
        'reversement_comptable' => 'Reversement comptable',
        _ => type,
      };

  bool get isDebit => type == 'decaissement_annulation' || type == 'reversement_comptable';
}

class ColisNature {
  final String id;
  final String libelle;
  final bool isActive;

  const ColisNature({required this.id, required this.libelle, required this.isActive});

  factory ColisNature.fromMap(Map<String, dynamic> map) => ColisNature(
        id: map['id'] as String,
        libelle: map['libelle'] as String,
        isActive: map['is_active'] as bool? ?? true,
      );
}

class RegisterColisInput {
  final String companyId;
  final String gareDepartId;
  final String gareDestinationId;
  final String nomExpediteur;
  final String telephoneExpediteur;
  final String nomDestinataire;
  final String telephoneDestinataire;
  final String? descriptionContenu;
  final double? poidsKg;
  final int nombrePieces;
  final double montantFret;
  /// Obligatoire — voir Colis.valeurMarchandise.
  final double valeurMarchandise;
  final double? pourcentagePercu;
  final List<String> natureIds;

  const RegisterColisInput({
    required this.companyId,
    required this.gareDepartId,
    required this.gareDestinationId,
    required this.nomExpediteur,
    required this.telephoneExpediteur,
    required this.nomDestinataire,
    required this.telephoneDestinataire,
    this.descriptionContenu,
    this.poidsKg,
    required this.nombrePieces,
    required this.montantFret,
    required this.valeurMarchandise,
    this.pourcentagePercu,
    required this.natureIds,
  });
}
