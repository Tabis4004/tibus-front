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
  /// Numéro de reçu séquentiel par gare de départ (migration 180) :
  /// 4 premiers caractères du nom de la gare + ordre sur 6 chiffres
  /// (ex. ABOI000001 pour le 1er colis d'Aboisso). Attribué par trigger en
  /// base — null uniquement pour un colis local hors connexion pas encore
  /// synchronisé ; les reçus retombent alors sur la référence CL-XXXXXXXX.
  final String? numeroRecu;
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
  /// Bus qui effectue le convoi — assignable à l'enregistrement ou au
  /// chargement (voir migration colis_bus_convoi, même logique que le web).
  final String? busId;
  /// Immatriculation du bus (affichage), voir busId.
  final String? busPlateNumber;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String gareDepart;
  /// Téléphone de la gare de départ — imprimé sur le reçu colis sous le
  /// nom de la gare, distinct du téléphone de la compagnie (voir
  /// colisReceiptLines / printer_service.dart). Vide si non renseigné par
  /// la compagnie pour cette gare.
  final String gareDepartPhone;
  final String gareDestination;
  /// Téléphone de la gare de destination — imprimé sur le reçu sous le
  /// champ Destination, symétrique à gareDepartPhone. Vide si non
  /// renseigné pour cette gare.
  final String gareDestinationPhone;
  final List<String> natures;
  /// Nom de la compagnie propriétaire du colis (choisi par la compagnie
  /// dans ses paramètres, ex. "SIS COURRIER") — déjà renvoyé par les RPC
  /// list_colis_autonomes / get_colis_autonome_detail (voir
  /// colis_detail_screen.dart), simplement absent du modèle jusqu'ici.
  /// Vide si non fourni : les reçus retombent alors sur 'TIBUS COURRIER'
  /// (voir colisReceiptLines et printer_service.dart).
  final String companyName;
  /// Téléphone de la compagnie — affiché en en-tête du reçu, sous le nom
  /// de la compagnie (distinct du téléphone de gare, voir gareDepartPhone).
  final String companyPhone;
  /// Chemin de stockage (bucket privé `colis-photos`) de la photo prise à
  /// l'enregistrement — voir colis_create_screen.dart. Null si aucune photo.
  /// Consultable sur ColisDetailScreen UNIQUEMENT : ne JAMAIS ajouter ce
  /// champ à colisReceiptLines / printer_service.dart (demande client : la
  /// photo ne doit jamais être imprimée sur le reçu).
  final String? photoPath;
  /// Vrai uniquement pour le Colis "local" construit à partir d'un
  /// PendingColis (enregistrement fait hors connexion, encore dans la file
  /// d'attente — voir offline_queue_service.dart / sync_service.dart).
  /// Toujours false pour un Colis reconstruit depuis les RPC (fromMap) :
  /// dès que la synchronisation réussit, le colis "réel" n'a plus ce flag.
  /// Sert uniquement à afficher la mention "REÇU PROVISOIRE" sur le reçu
  /// (colisReceiptLines / _ReceiptBox) tant que l'ID n'est pas confirmé par
  /// le serveur.
  final bool isPendingSync;

  const Colis({
    required this.id,
    this.numeroRecu,
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
    this.busId,
    this.busPlateNumber,
    required this.createdAt,
    required this.updatedAt,
    required this.gareDepart,
    this.gareDepartPhone = '',
    required this.gareDestination,
    this.gareDestinationPhone = '',
    required this.natures,
    this.companyName = '',
    this.companyPhone = '',
    this.photoPath,
    this.isPendingSync = false,
  });

  factory Colis.fromMap(Map<String, dynamic> map) {
    return Colis(
      id: map['id'] as String,
      numeroRecu: (map['numeroRecu'] as String?)?.trim(),
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
      busId: map['busId'] as String?,
      busPlateNumber: map['busPlateNumber'] as String?,
      createdAt: DateTime.tryParse(map['createdAt'] as String? ?? '') ?? DateTime.now(),
      updatedAt: DateTime.tryParse(map['updatedAt'] as String? ?? '') ?? DateTime.now(),
      gareDepart: map['gareDepart'] as String? ?? '',
      gareDepartPhone: (map['gareDepartPhone'] as String?)?.trim() ?? '',
      gareDestination: map['gareDestination'] as String? ?? '',
      gareDestinationPhone: (map['gareDestinationPhone'] as String?)?.trim() ?? '',
      natures: (map['natures'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      companyName: (map['companyName'] as String?)?.trim() ?? '',
      companyPhone: (map['companyPhone'] as String?)?.trim() ?? '',
      photoPath: map['photoPath'] as String?,
    );
  }
}

/// Bus actif de la compagnie, pour le sélecteur "bus du convoi" — reflète
/// la table Bus (même select direct que le web, voir listCompanyBusesSupabase
/// dans colis-autonomes.ts) : lecture publique pour les compagnies actives.
class BusOption {
  final String id;
  final String plateNumber;
  final String model;

  const BusOption({required this.id, required this.plateNumber, this.model = ''});

  factory BusOption.fromMap(Map<String, dynamic> map) => BusOption(
        id: map['id'] as String? ?? '',
        plateNumber: map['registrationNumber'] as String? ?? '',
        model: map['model'] as String? ?? '',
      );

  String get label => model.isNotEmpty ? '$plateNumber — $model' : plateNumber;
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

/// Montant du JOUR pour une agence (gare) — une ligne de la ventilation
/// affichée dans le bouton "Détail" de l'accueil agent, voir
/// get_colis_today_by_gare (migration add_get_colis_today_by_gare) et
/// ColisService.getColisTodayByGare.
class GareMontantJour {
  final String gareId;
  final String gareName;
  final int count;
  final double montant;

  const GareMontantJour({
    required this.gareId,
    required this.gareName,
    required this.count,
    required this.montant,
  });

  factory GareMontantJour.fromMap(Map<String, dynamic> map) => GareMontantJour(
        gareId: map['gareId'] as String? ?? '',
        gareName: map['gareName'] as String? ?? '',
        count: (map['count'] as num?)?.toInt() ?? 0,
        montant: (map['montant'] as num?)?.toDouble() ?? 0,
      );
}

/// Agent (vendeur) ayant enregistré au moins un colis pour la compagnie —
/// alimente le filtre "par agent" de la page Stats (voir
/// list_company_colis_vendeurs, stats_screen.dart). Inclut le owner s'il
/// vend lui-même : vendeur_id est le même champ pour tout le monde.
class ColisVendeur {
  final String id;
  final String name;

  const ColisVendeur({required this.id, required this.name});

  factory ColisVendeur.fromMap(Map<String, dynamic> map) => ColisVendeur(
        id: map['id'] as String? ?? '',
        name: map['name'] as String? ?? '',
      );
}

/// Une ligne du journal de vente — un colis (référence, date, expéditeur/
/// destinataire, frais/valeur, destination). Voir get_colis_sales_journal
/// (migration 192) et ColisSalesJournalPanel.tsx côté web pour le même
/// format imprimé.
class ColisSalesJournalLine {
  final String id;
  final String? numeroRecu;
  final DateTime createdAt;
  final String nomExpediteur;
  final String nomDestinataire;
  final double montantFret;
  final double? valeurMarchandise;
  final String gareDestination;

  const ColisSalesJournalLine({
    required this.id,
    required this.numeroRecu,
    required this.createdAt,
    required this.nomExpediteur,
    required this.nomDestinataire,
    required this.montantFret,
    required this.valeurMarchandise,
    required this.gareDestination,
  });

  factory ColisSalesJournalLine.fromMap(Map<String, dynamic> map) => ColisSalesJournalLine(
        id: map['id'] as String? ?? '',
        numeroRecu: map['numeroRecu'] as String?,
        createdAt: DateTime.tryParse(map['createdAt'] as String? ?? '') ?? DateTime.now(),
        nomExpediteur: map['nomExpediteur'] as String? ?? '',
        nomDestinataire: map['nomDestinataire'] as String? ?? '',
        montantFret: (map['montantFret'] as num?)?.toDouble() ?? 0,
        valeurMarchandise: (map['valeurMarchandise'] as num?)?.toDouble(),
        gareDestination: map['gareDestination'] as String? ?? '',
      );
}

/// Regroupement par agent (vendeur) du journal de vente, avec sous-total.
class ColisSalesJournalGroup {
  final String? vendeurId;
  final String vendeurName;
  final String? vendeurUsername;
  final List<ColisSalesJournalLine> colis;
  final int count;
  final double totalFrais;
  final double totalValeur;

  const ColisSalesJournalGroup({
    required this.vendeurId,
    required this.vendeurName,
    required this.vendeurUsername,
    required this.colis,
    required this.count,
    required this.totalFrais,
    required this.totalValeur,
  });

  factory ColisSalesJournalGroup.fromMap(Map<String, dynamic> map) => ColisSalesJournalGroup(
        vendeurId: map['vendeurId'] as String?,
        vendeurName: map['vendeurName'] as String? ?? 'Agent inconnu',
        vendeurUsername: map['vendeurUsername'] as String?,
        colis: (map['colis'] as List? ?? [])
            .whereType<Map<String, dynamic>>()
            .map(ColisSalesJournalLine.fromMap)
            .toList(),
        count: (map['count'] as num?)?.toInt() ?? 0,
        totalFrais: (map['totalFrais'] as num?)?.toDouble() ?? 0,
        totalValeur: (map['totalValeur'] as num?)?.toDouble() ?? 0,
      );
}

/// Journal de vente complet — colis vendus sur une période, groupés par
/// agent avec sous-total, + total général (get_colis_sales_journal,
/// migration 192). [fullAccess]/[gareScope] : même sémantique que
/// ColisStats, pour piloter l'affichage du filtre "par agent" côté écran.
class ColisSalesJournal {
  final List<ColisSalesJournalGroup> groups;
  final int grandCount;
  final double grandTotalFrais;
  final double grandTotalValeur;
  final bool fullAccess;
  final bool gareScope;

  const ColisSalesJournal({
    required this.groups,
    required this.grandCount,
    required this.grandTotalFrais,
    required this.grandTotalValeur,
    required this.fullAccess,
    required this.gareScope,
  });

  factory ColisSalesJournal.fromMap(Map<String, dynamic> map) => ColisSalesJournal(
        groups: (map['groups'] as List? ?? [])
            .whereType<Map<String, dynamic>>()
            .map(ColisSalesJournalGroup.fromMap)
            .toList(),
        grandCount: (map['grandCount'] as num?)?.toInt() ?? 0,
        grandTotalFrais: (map['grandTotalFrais'] as num?)?.toDouble() ?? 0,
        grandTotalValeur: (map['grandTotalValeur'] as num?)?.toDouble() ?? 0,
        fullAccess: map['fullAccess'] == true,
        gareScope: map['gareScope'] == true,
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
  /// Compagnie propriétaire de la gare de cette caisse — source de vérité
  /// serveur pour la "compagnie de travail" effective (voir
  /// activeCompanyIdProvider). Null si la RPC ne la renvoie pas encore
  /// (anciens déploiements) ou si aucune caisse n'est ouverte.
  final String? companyId;

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
    this.companyId,
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
        companyId: map['companyId'] as String?,
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
  /// Bus qui effectue le convoi, si déjà connu à l'enregistrement (optionnel).
  final String? busId;
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
    this.busId,
    this.poidsKg,
    required this.nombrePieces,
    required this.montantFret,
    required this.valeurMarchandise,
    this.pourcentagePercu,
    required this.natureIds,
  });
}
