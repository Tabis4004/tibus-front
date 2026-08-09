import 'dart:convert';
import 'dart:math';
import 'colis.dart';

/// Génère un identifiant local unique (hors-ligne, avant tout appel réseau)
/// — pas besoin d'un vrai UUID (pas de dépendance ajoutée) : timestamp +
/// suffixe aléatoire suffisent, cet id ne sert qu'à titre local (clé de la
/// file d'attente, référence provisoire imprimée sur le reçu).
String generateLocalId() {
  final rand = Random();
  final suffix = List.generate(8, (_) => rand.nextInt(16).toRadixString(16)).join();
  return 'local-${DateTime.now().millisecondsSinceEpoch}-$suffix';
}

/// Colis enregistré alors que l'appareil était hors connexion — en attente
/// d'un appel réussi à register_colis_autonome (voir OfflineQueueService,
/// SyncService). Contient à la fois les paramètres exacts de l'appel RPC
/// (pour rejouer l'enregistrement à l'identique une fois reconnecté) et un
/// instantané des libellés d'affichage (gares/compagnie/nature) au moment
/// de la création, pour pouvoir afficher/réimprimer le reçu provisoire et
/// la liste d'attente sans dépendre du réseau.
class PendingColis {
  final String localId;
  final DateTime createdAt;

  // --- Paramètres register_colis_autonome (voir RegisterColisInput) ---
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
  final double valeurMarchandise;
  final double? pourcentagePercu;
  final String? busId;
  final List<String> natureIds;

  // --- Instantané d'affichage (gares/compagnie/nature au moment de la
  // création — évite de dépendre du réseau pour la liste d'attente et le
  // reçu provisoire) ---
  final String gareDepartName;
  final String gareDepartPhone;
  final String gareDestinationName;
  final String gareDestinationPhone;
  final String companyName;
  final String companyPhone;
  final String natureLabel;

  /// Photo prise hors-ligne (voir colis_create_screen.dart), encodée en
  /// base64 pour la persistance JSON — uploadée seulement au moment de la
  /// synchronisation réussie (voir SyncService), jamais avant.
  final String? photoBase64;

  /// Message d'erreur de la dernière tentative de synchronisation échouée
  /// (ex. erreur de validation serveur — montant insuffisant, gare
  /// invalide...) — affiché dans la file d'attente pour que l'agent puisse
  /// corriger ou signaler le cas. Null tant qu'aucune tentative n'a échoué.
  final String? lastError;
  final int attempts;

  /// Id auth Supabase (AuthService.currentAuthUserId) de l'agent connecté au
  /// moment de la création — sert à restreindre la synchronisation
  /// AUTOMATIQUE à cet agent (voir SyncService.syncMine), pour éviter qu'un
  /// autre agent connecté ensuite sur le même appareil (relève de guichet,
  /// tablette partagée) ne synchronise involontairement ce colis en son
  /// propre nom : register_colis_autonome attribue le colis à qui APPELLE
  /// la RPC, pas à qui l'a saisi. Nullable et volontairement permissif : un
  /// colis existant AVANT cette protection (créé sans ce champ, donc null)
  /// reste synchronisable par n'importe quel agent, exactement comme avant —
  /// il n'y a pas d'info d'origine à retrouver rétroactivement pour ces
  /// entrées-là, mieux vaut les laisser se synchroniser (et donc se
  /// comptabiliser) que les bloquer indéfiniment.
  final String? creatorUserId;

  const PendingColis({
    required this.localId,
    required this.createdAt,
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
    this.busId,
    required this.natureIds,
    required this.gareDepartName,
    this.gareDepartPhone = '',
    required this.gareDestinationName,
    this.gareDestinationPhone = '',
    this.companyName = '',
    this.companyPhone = '',
    this.natureLabel = '',
    this.photoBase64,
    this.lastError,
    this.attempts = 0,
    this.creatorUserId,
  });

  RegisterColisInput toInput() => RegisterColisInput(
        companyId: companyId,
        gareDepartId: gareDepartId,
        gareDestinationId: gareDestinationId,
        nomExpediteur: nomExpediteur,
        telephoneExpediteur: telephoneExpediteur,
        nomDestinataire: nomDestinataire,
        telephoneDestinataire: telephoneDestinataire,
        descriptionContenu: descriptionContenu,
        poidsKg: poidsKg,
        nombrePieces: nombrePieces,
        montantFret: montantFret,
        valeurMarchandise: valeurMarchandise,
        pourcentagePercu: pourcentagePercu,
        busId: busId,
        natureIds: natureIds,
      );

  /// Colis "provisoire" affiché/imprimé immédiatement (voir
  /// colis_create_screen.dart, pending_colis_screen.dart) — id local
  /// distinct d'un vrai id serveur (préfixe "local-"), isPendingSync=true
  /// pour que colisReceiptLines()/_ReceiptBox affichent la mention
  /// provisoire (voir colis_receipt_lines.dart).
  Colis toColis() => Colis(
        id: localId,
        statut: ColisStatut.enregistre,
        nomExpediteur: nomExpediteur,
        telephoneExpediteur: telephoneExpediteur,
        nomDestinataire: nomDestinataire,
        telephoneDestinataire: telephoneDestinataire,
        descriptionContenu: descriptionContenu,
        poidsKg: poidsKg,
        nombrePieces: nombrePieces,
        montantFret: montantFret,
        valeurMarchandise: valeurMarchandise,
        pourcentagePercu: pourcentagePercu,
        busId: busId,
        createdAt: createdAt,
        updatedAt: createdAt,
        gareDepart: gareDepartName,
        gareDepartPhone: gareDepartPhone,
        gareDestination: gareDestinationName,
        gareDestinationPhone: gareDestinationPhone,
        natures: natureLabel.isEmpty ? const [] : [natureLabel],
        companyName: companyName,
        companyPhone: companyPhone,
        isPendingSync: true,
      );

  PendingColis copyWith({String? lastError, int? attempts, bool clearError = false}) => PendingColis(
        localId: localId,
        createdAt: createdAt,
        companyId: companyId,
        gareDepartId: gareDepartId,
        gareDestinationId: gareDestinationId,
        nomExpediteur: nomExpediteur,
        telephoneExpediteur: telephoneExpediteur,
        nomDestinataire: nomDestinataire,
        telephoneDestinataire: telephoneDestinataire,
        descriptionContenu: descriptionContenu,
        poidsKg: poidsKg,
        nombrePieces: nombrePieces,
        montantFret: montantFret,
        valeurMarchandise: valeurMarchandise,
        pourcentagePercu: pourcentagePercu,
        busId: busId,
        natureIds: natureIds,
        gareDepartName: gareDepartName,
        gareDepartPhone: gareDepartPhone,
        gareDestinationName: gareDestinationName,
        gareDestinationPhone: gareDestinationPhone,
        companyName: companyName,
        companyPhone: companyPhone,
        natureLabel: natureLabel,
        photoBase64: photoBase64,
        lastError: clearError ? null : (lastError ?? this.lastError),
        attempts: attempts ?? this.attempts,
        creatorUserId: creatorUserId,
      );

  Map<String, dynamic> toJson() => {
        'localId': localId,
        'createdAt': createdAt.toIso8601String(),
        'companyId': companyId,
        'gareDepartId': gareDepartId,
        'gareDestinationId': gareDestinationId,
        'nomExpediteur': nomExpediteur,
        'telephoneExpediteur': telephoneExpediteur,
        'nomDestinataire': nomDestinataire,
        'telephoneDestinataire': telephoneDestinataire,
        'descriptionContenu': descriptionContenu,
        'poidsKg': poidsKg,
        'nombrePieces': nombrePieces,
        'montantFret': montantFret,
        'valeurMarchandise': valeurMarchandise,
        'pourcentagePercu': pourcentagePercu,
        'busId': busId,
        'natureIds': natureIds,
        'gareDepartName': gareDepartName,
        'gareDepartPhone': gareDepartPhone,
        'gareDestinationName': gareDestinationName,
        'gareDestinationPhone': gareDestinationPhone,
        'companyName': companyName,
        'companyPhone': companyPhone,
        'natureLabel': natureLabel,
        'photoBase64': photoBase64,
        'lastError': lastError,
        'attempts': attempts,
        'creatorUserId': creatorUserId,
      };

  factory PendingColis.fromJson(Map<String, dynamic> map) => PendingColis(
        localId: map['localId'] as String,
        createdAt: DateTime.tryParse(map['createdAt'] as String? ?? '') ?? DateTime.now(),
        companyId: map['companyId'] as String? ?? '',
        gareDepartId: map['gareDepartId'] as String? ?? '',
        gareDestinationId: map['gareDestinationId'] as String? ?? '',
        nomExpediteur: map['nomExpediteur'] as String? ?? '',
        telephoneExpediteur: map['telephoneExpediteur'] as String? ?? '',
        nomDestinataire: map['nomDestinataire'] as String? ?? '',
        telephoneDestinataire: map['telephoneDestinataire'] as String? ?? '',
        descriptionContenu: map['descriptionContenu'] as String?,
        poidsKg: (map['poidsKg'] as num?)?.toDouble(),
        nombrePieces: (map['nombrePieces'] as num?)?.toInt() ?? 1,
        montantFret: (map['montantFret'] as num?)?.toDouble() ?? 0,
        valeurMarchandise: (map['valeurMarchandise'] as num?)?.toDouble() ?? 0,
        pourcentagePercu: (map['pourcentagePercu'] as num?)?.toDouble(),
        busId: map['busId'] as String?,
        natureIds: (map['natureIds'] as List?)?.map((e) => e.toString()).toList() ?? const [],
        gareDepartName: map['gareDepartName'] as String? ?? '',
        gareDepartPhone: map['gareDepartPhone'] as String? ?? '',
        gareDestinationName: map['gareDestinationName'] as String? ?? '',
        gareDestinationPhone: map['gareDestinationPhone'] as String? ?? '',
        companyName: map['companyName'] as String? ?? '',
        companyPhone: map['companyPhone'] as String? ?? '',
        natureLabel: map['natureLabel'] as String? ?? '',
        photoBase64: map['photoBase64'] as String?,
        lastError: map['lastError'] as String?,
        attempts: (map['attempts'] as num?)?.toInt() ?? 0,
        // Absent pour toute entrée créée avant cette mise à jour (JSON déjà
        // persisté) — `as String?` sur une clé manquante renvoie null
        // naturellement, ce qui les rend synchronisables par n'importe quel
        // agent (voir doc du champ ci-dessus), sans migration nécessaire.
        creatorUserId: map['creatorUserId'] as String?,
      );

  static String encodeList(List<PendingColis> list) => jsonEncode(list.map((e) => e.toJson()).toList());

  static List<PendingColis> decodeList(String raw) {
    final decoded = jsonDecode(raw) as List;
    return decoded.whereType<Map<String, dynamic>>().map(PendingColis.fromJson).toList();
  }
}
