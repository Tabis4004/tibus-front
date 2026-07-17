import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/utils/bordereau_receipt_lines.dart';
import '../../core/utils/colis_receipt_lines.dart';
import '../models/colis.dart';
import 'bordereau_service.dart';
import 'esc_pos_printer_service.dart';
import 'pos_bridge/pos_bridge.dart';

export 'esc_pos_printer_service.dart' show EscPosPrinterService;
export 'package:flutter_pos_printer_platform_image_3/flutter_pos_printer_platform_image_3.dart'
    show PrinterDevice, PrinterType;

/// Impression sur reçu papier côté guichet — même logique multi-pont que
/// Tibus web (src/lib/webview-bridge.ts, src/lib/colis-receipt.ts,
/// src/lib/ticket-receipt-print.ts) : imprimante P3/Wiseasy intégrée
/// (Android natif, SDK Wangpos — mêmes fichiers que tibus-v2-HUB, voir
/// android/app/libs/ et android/app/src/main/kotlin/com/tibus/courrier/
/// printer/), pont Xprinter/WisePrinter (desktop, si ce build web tourne
/// dans un wrapper qui l'expose sur `window`), puis fallback impression
/// navigateur (toujours disponible, aucun pont requis).
///
/// Ne remplace PAS le suivi/push (voir push_service.dart) : sert uniquement
/// à imprimer un reçu papier côté guichet.
class PrinterService {
  static const _channel = MethodChannel('com.tibus.courrier/p3_printer');
  final PosBridge _bridge = createPosBridge();
  EscPosPrinterService? _escPos;

  bool get isAvailable =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Imprimante P3/Wiseasy intégrée — Android natif uniquement.
  bool get hasNativeP3 => isAvailable;

  /// Pont Xprinter/WisePrinter (desktop) détecté sur `window` — actif
  /// uniquement sur le build web, quand un wrapper l'injecte (même contrat
  /// que window.WisePrinter côté Tibus web).
  bool get hasWisePrinterBridge => _bridge.hasWisePrinter;

  /// Pont USB/Bluetooth ESC/POS (flutter_pos_printer_platform_image_3) —
  /// couvre les imprimantes physiques réelles du guichet (Xprinter XP-Q200
  /// en USB, Mini Printer MPT-II en Bluetooth) qui ne sont ni l'imprimante
  /// P3 intégrée, ni un pont desktop `window`. Disponible partout sauf web
  /// (le plugin n'implémente pas de pont navigateur).
  bool get hasEscPosSupport => !kIsWeb;

  /// Découverte/connexion/impression USB & Bluetooth — voir
  /// esc_pos_printer_service.dart.
  EscPosPrinterService get escPos => _escPos ??= EscPosPrinterService();

  Future<void> warmUp() async {
    if (!isAvailable) return;
    try {
      await _channel.invokeMethod('warmUp');
    } catch (_) {
      // Best-effort : appareil sans imprimante P3 intégrée.
    }
  }

  Future<Map<String, dynamic>?> status() async {
    if (!isAvailable) return null;
    try {
      final result = await _channel.invokeMethod('status');
      return (result as Map?)?.cast<String, dynamic>();
    } catch (_) {
      return null;
    }
  }

  /// Reçu structuré (recommandé) : en-tête centré, lignes label/valeur,
  /// QR optionnel, pied de page. Correspond à l'API structurée de
  /// P3PrinterModule.printReceipt58/80(header, reference, rows, qr, footer).
  Future<void> printReceipt({
    required List<String> header,
    required String reference,
    required List<List<String>> rows,
    String qr = '',
    String footer = 'Powered by Tibus',
    int paperWidthMm = 58,
  }) async {
    if (!isAvailable) {
      throw StateError('Imprimante P3 indisponible sur cet appareil.');
    }
    await _channel.invokeMethod('printReceiptStructured', {
      'header': header,
      'reference': reference,
      'rows': rows,
      'qr': qr,
      'footer': footer,
      'paperWidthMm': paperWidthMm,
    });
  }

  /// Nom de l'agent connecté, pour le champ "Agent" du reçu — best-effort,
  /// lu depuis les métadonnées Supabase Auth (full_name), jamais une requête
  /// réseau supplémentaire. `null`/vide si indisponible : la ligne est alors
  /// simplement omise (voir colisReceiptLines).
  String? _currentAgentName() {
    try {
      final meta = Supabase.instance.client.auth.currentUser?.userMetadata;
      final name = meta?['full_name'] as String?;
      return (name != null && name.trim().isNotEmpty) ? name.trim() : null;
    } catch (_) {
      return null;
    }
  }

  /// Reçu pour un colis — format "propre et encadré" (en-tête, N° en
  /// évidence, blocs EXPÉDITEUR / BÉNÉFICIAIRE / CONTENU), avec le code de
  /// retrait en QR pour un scan rapide côté destinataire. Voir
  /// colis_receipt_lines.dart pour le même contenu côté ponts
  /// WisePrinter/ESC-POS (colisReceiptLines) — ici en rows label/valeur
  /// (API structurée du pont P3 natif, qui ne connaît pas les sections en
  /// gras : les libellés EXPÉDITEUR/BÉNÉFICIAIRE/CONTENU servent de repère
  /// visuel en l'absence de mise en forme riche côté imprimante intégrée).
  Future<void> printColisReceipt(Colis colis, {int paperWidthMm = 58, String? agentName}) {
    final agent = agentName ?? _currentAgentName();
    return printReceipt(
      header: [
        colis.companyName.isNotEmpty ? colis.companyName : 'TIBUS COURRIER',
        // Téléphone du SIÈGE (compagnie) sous le nom de la compagnie, et
        // téléphone de la gare de DESTINATION juste en dessous — le
        // téléphone de la gare de DÉPART est lui affiché dans le bloc
        // EXPÉDITEUR ci-dessous (voir rows, ligne "Tél. agence").
        if (colis.companyPhone.isNotEmpty) 'Tél siège: ${colis.companyPhone}',
        if (colis.gareDestinationPhone.isNotEmpty) 'Tél dest: ${colis.gareDestinationPhone}',
        // Sous-titre EXPLICITE : sans lui, le module P3 natif retombe sur
        // « Ticket » par défaut (normalizeStructured, P3PrinterModule.kt).
        'Reçu expédition colis',
      ],
      // Numéro séquentiel par gare (ex. ABOI000001) — repli CL-XXXXXXXX.
      reference: colisReceiptNumber(colis),
      rows: [
        ['EXPÉDITEUR', colis.nomExpediteur],
        ['Téléphone', colis.telephoneExpediteur],
        ["Frais d'envoi", '${colis.montantFret.toStringAsFixed(0)} FCFA'],
        if (colis.valeurMarchandise != null && colis.valeurMarchandise! > 0)
          ['Valeur', '${colis.valeurMarchandise!.toStringAsFixed(0)} FCFA'],
        ['Agence', colis.gareDepart],
        if (colis.gareDepartPhone.isNotEmpty) ['Tél. agence', colis.gareDepartPhone],
        if (agent != null) ['Agent', agent],
        ['Déposé le', formatColisDate(colis.createdAt)],
        ['BÉNÉFICIAIRE', colis.nomDestinataire],
        ['Téléphone ', colis.telephoneDestinataire],
        ['Destination', colis.gareDestination],
        // Tél. destination déplacé en en-tête (voir header ci-dessus).
        ['CONTENU', ''],
        ['Nature du colis', colisNatureLabel(colis)],
        ['Description', colisDescriptionLabel(colis)],
        if (colis.poidsKg != null) ['Poids', '${colis.poidsKg} kg'],
        if (colis.pourcentagePercu != null && colis.pourcentagePercu! > 0)
          ['Pourcentage perçu', '${colis.pourcentagePercu} %'],
      ],
      // Pas de QR sur le reçu client — voir demande "enlever le QR code du
      // reçu du client". Le QR reste sur le talon (printColisTalon
      // ci-dessous), nécessaire au scan pendant chargement/arrivée/livraison.
      qr: '',
      // Tiret ASCII (pas « — ») : le cadratin faisait perdre le « R » de
      // « Retrait » au rendu P3 (« etrait sous 72h » sur le papier).
      footer: 'Retrait sous 72h - passé ce délai,\nfrais de magasinage.\nPowered by Tibus',
      paperWidthMm: paperWidthMm,
    );
  }

  /// Talon (étiquette adhésive à coller sur le colis) — imprimé à la suite
  /// du reçu, voir printColisReceiptWithTalon. Contenu volontairement
  /// minimal (référence, destination, montant, destinataire, expéditeur) :
  /// c'est ce qui reste collé sur le colis physique, pas un document à
  /// conserver par le client.
  Future<void> printColisTalon(Colis colis, {int paperWidthMm = 58}) {
    return printReceipt(
      header: [
        colis.companyName.isNotEmpty ? colis.companyName : 'TIBUS COURRIER',
        // Même en-tête que le reçu (voir printColisReceipt) : téléphone du
        // siège (compagnie) ET de la gare de destination, puis sous-titre
        // explicite — sans lui, le module P3 natif retombe sur « Ticket ».
        // Le téléphone de la gare de départ est lui dans le bloc expédition
        // ci-dessous (ligne "Tél. agence").
        if (colis.companyPhone.isNotEmpty) 'Tél siège: ${colis.companyPhone}',
        if (colis.gareDestinationPhone.isNotEmpty) 'Tél dest: ${colis.gareDestinationPhone}',
        'Reçu expédition colis',
      ],
      reference: colisReceiptNumber(colis),
      rows: [
        ['Destination', colis.gareDestination],
        ['Montant', '${colis.montantFret.toStringAsFixed(0)} FCFA'],
        ['Destinataire', colis.nomDestinataire],
        ['Téléphone', colis.telephoneDestinataire],
        ['Expéditeur', colis.nomExpediteur],
        ['Tél. exp.', colis.telephoneExpediteur],
        ['Agence', colis.gareDepart],
        if (colis.gareDepartPhone.isNotEmpty) ['Tél. agence', colis.gareDepartPhone],
      ],
      qr: colis.id,
      footer: '',
      paperWidthMm: paperWidthMm,
    );
  }

  /// Reçu + talon en une seule action ("sur le même envoi") — imprimante
  /// P3 intégrée. Deux impressions successives (chacune terminée par une
  /// coupe, voir P3PrinterModule.finishPrinter) : le reçu pour le client,
  /// le talon à détacher et coller sur le colis.
  Future<void> printColisReceiptWithTalon(Colis colis, {int paperWidthMm = 58, String? agentName}) async {
    await printColisReceipt(colis, paperWidthMm: paperWidthMm, agentName: agentName);
    await printColisTalon(colis, paperWidthMm: paperWidthMm);
  }

  /// Bordereau de livraison — pont P3 natif. Une ligne rows par colis
  /// (référence + destinataire/montant), voir bordereauReceiptLines pour le
  /// même contenu côté WisePrinter/ESC-POS.
  Future<void> printBordereau(BordereauDetail d, {int paperWidthMm = 58}) {
    final trajet = '${d.gareDepart} -> ${d.gareDestination ?? "Toutes destinations"}';
    return printReceipt(
      header: [d.companyName.isNotEmpty ? d.companyName : 'TIBUS COURRIER', 'Bordereau de livraison'],
      reference: d.reference,
      rows: [
        ['Trajet', trajet],
        if (d.busPlateNumber != null) ['Bus', d.busPlateNumber!],
        if (d.createdAt != null) ['Créé le', formatBordereauDate(d.createdAt!)],
        ['Colis', '${d.colis.length}'],
        for (var i = 0; i < d.colis.length; i++)
          [
            '${i + 1}. ${d.colis[i].reference}',
            '${d.colis[i].nomDestinataire} · ${d.colis[i].montantFret.toStringAsFixed(0)} FCFA',
          ],
        ['Total fret', '${d.totalFret.toStringAsFixed(0)} FCFA'],
      ],
      qr: d.id,
      footer: 'Powered by Tibus',
      paperWidthMm: paperWidthMm,
    );
  }

  /// Bordereau de livraison — pont Xprinter/WisePrinter (desktop).
  Future<void> printBordereauViaWisePrinter(BordereauDetail d) {
    if (!hasWisePrinterBridge) {
      throw StateError('Xprinter indisponible sur cet appareil.');
    }
    return _bridge.printViaWisePrinter(
      header: d.companyName.isNotEmpty ? d.companyName : 'TIBUS COURRIER',
      lines: bordereauReceiptLines(d),
      qr: d.id,
      qrSize: 200,
      feedLines: 4,
      cut: true,
    );
  }

  Future<void> release() async {
    if (!isAvailable) return;
    try {
      await _channel.invokeMethod('release');
    } catch (_) {
      // best-effort
    }
  }

  /// Reçu colis via le pont Xprinter/WisePrinter (desktop) — même contrat
  /// que printer.printReceipt() côté web (src/lib/printer.ts).
  Future<void> printColisReceiptViaWisePrinter(Colis colis, {String? agentName}) {
    if (!hasWisePrinterBridge) {
      throw StateError('Xprinter indisponible sur cet appareil.');
    }
    return _bridge.printViaWisePrinter(
      header: colis.companyName.isNotEmpty ? colis.companyName : 'TIBUS COURRIER',
      lines: colisReceiptLines(colis, agentName: agentName ?? _currentAgentName()),
      // Pas de QR sur le reçu client — voir printColisReceipt (pont P3) et
      // demande "enlever le QR code du reçu du client".
      qr: '',
      qrSize: 220,
      feedLines: 4,
      cut: true,
    );
  }

  /// Talon via le pont Xprinter/WisePrinter — voir printColisTalon (pont P3).
  Future<void> printColisTalonViaWisePrinter(Colis colis) {
    if (!hasWisePrinterBridge) {
      throw StateError('Xprinter indisponible sur cet appareil.');
    }
    return _bridge.printViaWisePrinter(
      header: colis.companyName.isNotEmpty ? colis.companyName : 'TIBUS COURRIER',
      lines: colisTalonLines(colis),
      qr: colis.id,
      qrSize: 220,
      feedLines: 3,
      cut: true,
    );
  }

  /// Reçu + talon en une seule action — pont Xprinter/WisePrinter.
  Future<void> printColisReceiptWithTalonViaWisePrinter(Colis colis, {String? agentName}) async {
    await printColisReceiptViaWisePrinter(colis, agentName: agentName);
    await printColisTalonViaWisePrinter(colis);
  }

  /// Fallback impression navigateur — toujours disponible, aucun pont natif
  /// requis (même logique que printColisReceiptBrowser() côté web,
  /// src/lib/colis-receipt.ts). Retourne `false` hors web. Le talon est
  /// visible dans le même aperçu que le reçu (voir
  /// colis_receipt_preview_sheet.dart) : une seule impression navigateur
  /// capture les deux.
  bool printColisReceiptBrowser({bool wide = true}) {
    return _bridge.triggerBrowserPrint(wide: wide);
  }
}
