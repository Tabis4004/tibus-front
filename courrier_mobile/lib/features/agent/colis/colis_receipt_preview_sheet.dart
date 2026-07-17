import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/providers.dart';
import '../../../core/utils/colis_receipt_lines.dart';
import '../../../core/utils/sms.dart';
import '../../../data/models/colis.dart';
import '../../../data/services/printer_service.dart' show PrinterDevice, PrinterType;

/// Message texte de partage du reçu (SMS) — même contenu informatif que le
/// reçu papier, pour envoi manuel à l'expéditeur ou au destinataire (voir
/// buildColisTrackingWhatsAppMessage côté web, src/lib/colis-receipt.ts).
/// WhatsApp partage désormais une image du reçu (voir _shareReceiptImage) :
/// wa.me ne permet de pré-remplir que du texte, jamais une image jointe à un
/// contact précis — un vrai reçu visuel nécessite le partage fichier.
String _colisTextShareMessage(Colis colis) {
  final ref = colisShortRef(colis);
  final company = colis.companyName.isNotEmpty ? colis.companyName : 'TIBUS COURRIER';
  return [
    '$company — Reçu colis $ref',
    'Trajet : ${colis.gareDepart} -> ${colis.gareDestination}',
    'Contenu : ${colisContentLabel(colis)}',
    "Frais d'envoi : ${colis.montantFret.toStringAsFixed(0)} FCFA",
    '',
    'Expéditeur : ${colis.nomExpediteur} (${colis.telephoneExpediteur})',
    'Destinataire : ${colis.nomDestinataire} (${colis.telephoneDestinataire})',
    '',
    'Retrait sous 72h — passé ce délai, des frais de magasinage sont imputables.',
  ].join('\n');
}

/// Nom de l'agent connecté pour l'affichage — même lecture best-effort que
/// PrinterService._currentAgentName (métadonnées Supabase Auth uniquement,
/// jamais de requête réseau supplémentaire).
String? _currentAgentDisplayName() {
  try {
    final meta = Supabase.instance.client.auth.currentUser?.userMetadata;
    final name = meta?['full_name'] as String?;
    return (name != null && name.trim().isNotEmpty) ? name.trim() : null;
  } catch (_) {
    return null;
  }
}

/// Aperçu du reçu colis + talon avant impression, avec sélection explicite
/// du pont imprimante — même logique multi-pont que côté web
/// (src/lib/colis-receipt.ts, src/lib/ticket-receipt-print.ts) :
/// - "Xprinter" -> pont desktop (window.WisePrinter), si détecté ;
/// - "56 mm (Wiseasy P3)" -> imprimante intégrée, Android natif ;
/// - "80 mm Xprinter (toujours disponible)" -> pont desktop si présent,
///   sinon fallback impression navigateur (fonctionne partout) ;
/// - "USB / Bluetooth" -> imprimante physique réelle (Xprinter, Mini
///   Printer...) via esc_pos_printer_service.dart.
///
/// Chaque bouton imprime le REÇU (à conserver) ET le TALON (étiquette à
/// détacher et coller sur le colis) en une seule action — format "propre et
/// encadré" repris d'un modèle papier de référence (voir
/// colis_receipt_lines.dart).
Future<void> showColisReceiptPreview(BuildContext context, Colis colis) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) => _ColisReceiptPreviewSheet(colis: colis),
  );
}

class _ColisReceiptPreviewSheetState extends ConsumerState<_ColisReceiptPreviewSheet> {
  bool _printing = false;
  bool _sharingImage = false;
  final _receiptImageKey = GlobalKey();

  /// Capture le cadre du reçu (RepaintBoundary ci-dessous) en PNG et ouvre la
  /// feuille de partage native — WhatsApp y figure comme n'importe quelle
  /// autre app, mais avec l'image réelle du reçu (et non plus juste du
  /// texte). Contrainte de la plateforme : wa.me ne sait pré-remplir qu'un
  /// texte, donc impossible de viser directement une conversation WhatsApp
  /// précise avec un fichier joint — l'utilisateur choisit le contact après
  /// avoir sélectionné WhatsApp dans la feuille de partage.
  Future<void> _shareReceiptImage(String label) async {
    if (_sharingImage) return;
    setState(() => _sharingImage = true);
    try {
      final boundary = _receiptImageKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final bytes = byteData!.buffer.asUint8List();
      final ref = colisShortRef(widget.colis);
      await Share.shareXFiles(
        [XFile.fromData(bytes, name: 'recu_$ref.png', mimeType: 'image/png')],
        text: 'Reçu colis $ref — pour le $label.',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Partage impossible : $e')));
      }
    } finally {
      if (mounted) setState(() => _sharingImage = false);
    }
  }

  Future<void> _shareSms(String phone, String label) async {
    final message = _colisTextShareMessage(widget.colis);
    final ok = await openSms(phone, message);
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Numéro $label manquant ou invalide, ou app SMS indisponible.')));
    }
  }

  Future<void> _run(Future<void> Function() action, {String? successMessage}) async {
    if (_printing) return;
    setState(() => _printing = true);
    try {
      await action();
      if (mounted && successMessage != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(successMessage)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur impression : $e')));
      }
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final printer = ref.read(printerServiceProvider);
    final colis = widget.colis;
    final agentName = _currentAgentDisplayName();

    // Tout le contenu (aperçu + boutons) est désormais dans UN SEUL scroll,
    // borné à ~90% de la hauteur de l'écran : sur une fenêtre desktop/macOS
    // courte, l'ancienne structure (aperçu scrollable à part, boutons hors
    // scroll) provoquait un "BOTTOM OVERFLOWED" qui masquait les boutons
    // d'impression sous la fenêtre.
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.9),
        child: SingleChildScrollView(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: MediaQuery.of(context).viewInsets.bottom + 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text('Aperçu du reçu', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              RepaintBoundary(
                key: _receiptImageKey,
                child: _ReceiptBox(colis: colis, agentName: agentName),
              ),
              const SizedBox(height: 12),
              Row(
                children: const [
                  Expanded(child: Divider()),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Text('Talon à coller sur le colis', style: TextStyle(fontSize: 11, color: Colors.grey)),
                  ),
                  Expanded(child: Divider()),
                ],
              ),
              const SizedBox(height: 8),
              _TalonBox(colis: colis),
              const SizedBox(height: 16),
              Text(
                'Choisir une imprimante (reçu + talon)',
                style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.secondary, fontSize: 12),
              ),
              const SizedBox(height: 8),
              _PrinterButton(
                icon: Icons.print_outlined,
                label: 'Xprinter',
                enabled: !_printing && printer.hasWisePrinterBridge,
                disabledHint: printer.hasWisePrinterBridge ? null : 'Xprinter non détecté sur cet appareil',
                onPressed: () => _run(
                  () => printer.printColisReceiptWithTalonViaWisePrinter(colis, agentName: agentName),
                  successMessage: 'Reçu + talon envoyés (Xprinter).',
                ),
              ),
              const SizedBox(height: 8),
              // Parcours guichet à l'enregistrement : UNE action imprime le
              // reçu (remis au client) PUIS le talon (collé sur le colis).
              _PrinterButton(
                icon: Icons.receipt_long,
                label: 'Reçu + talon (56 mm P3)',
                enabled: !_printing && printer.hasNativeP3,
                disabledHint: printer.hasNativeP3 ? null : 'Imprimante intégrée non détectée (Android requis)',
                onPressed: () => _run(
                  () => printer.printColisReceiptWithTalon(colis, paperWidthMm: 58, agentName: agentName),
                  successMessage: 'Reçu (client) puis talon (à coller) envoyés — 56 mm.',
                ),
              ),
              const SizedBox(height: 8),
              // Réimpressions séparées ultérieures (depuis le détail du colis).
              Row(
                children: [
                  Expanded(
                    child: _PrinterButton(
                      icon: Icons.receipt_long_outlined,
                      label: 'Reçu seul (56 mm P3)',
                      enabled: !_printing && printer.hasNativeP3,
                      disabledHint: printer.hasNativeP3 ? null : 'Imprimante intégrée non détectée (Android requis)',
                      onPressed: () => _run(
                        () => printer.printColisReceipt(colis, paperWidthMm: 58, agentName: agentName),
                        successMessage: 'Reçu envoyé (imprimante intégrée, 56 mm).',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _PrinterButton(
                      icon: Icons.label_outline,
                      label: 'Talon seul (56 mm P3)',
                      enabled: !_printing && printer.hasNativeP3,
                      disabledHint: printer.hasNativeP3 ? null : 'Imprimante intégrée non détectée (Android requis)',
                      onPressed: () => _run(
                        () => printer.printColisTalon(colis, paperWidthMm: 58),
                        successMessage: 'Talon envoyé (56 mm) — à coller sur le colis.',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _PrinterButton(
                icon: Icons.local_print_shop_outlined,
                label: '80 mm Xprinter (toujours disponible)',
                enabled: !_printing,
                onPressed: () => _run(() async {
                  if (printer.hasWisePrinterBridge) {
                    await printer.printColisReceiptWithTalonViaWisePrinter(colis, agentName: agentName);
                    return;
                  }
                  final ok = printer.printColisReceiptBrowser(wide: true);
                  if (!ok) throw StateError('Impression navigateur indisponible sur cet appareil.');
                }, successMessage: 'Impression envoyée (80 mm).'),
              ),
              const SizedBox(height: 8),
              _PrinterButton(
                icon: Icons.usb,
                label: 'USB / Bluetooth / Réseau (Xprinter, YHD-8390…)',
                enabled: !_printing && printer.hasEscPosSupport,
                disabledHint: printer.hasEscPosSupport
                    ? null
                    : 'Disponible uniquement sur l\'app native (Android/iOS/Windows)',
                onPressed: () => showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => _EscPosPrinterSheet(colis: colis, agentName: agentName),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Partager le reçu (image) — WhatsApp, etc.',
                style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.secondary, fontSize: 12),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _PrinterButton(
                      icon: Icons.chat,
                      label: 'Expéditeur',
                      enabled: !_sharingImage,
                      onPressed: () => _shareReceiptImage('expéditeur'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _PrinterButton(
                      icon: Icons.chat,
                      label: 'Destinataire',
                      enabled: !_sharingImage,
                      onPressed: () => _shareReceiptImage('destinataire'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                'Partager par SMS (texte)',
                style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.secondary, fontSize: 12),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _PrinterButton(
                      icon: Icons.sms_outlined,
                      label: 'Expéditeur',
                      enabled: true,
                      onPressed: () => _shareSms(colis.telephoneExpediteur, 'expéditeur'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _PrinterButton(
                      icon: Icons.sms_outlined,
                      label: 'Destinataire',
                      enabled: true,
                      onPressed: () => _shareSms(colis.telephoneDestinataire, 'destinataire'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ColisReceiptPreviewSheet extends ConsumerStatefulWidget {
  final Colis colis;
  const _ColisReceiptPreviewSheet({required this.colis});

  @override
  ConsumerState<_ColisReceiptPreviewSheet> createState() => _ColisReceiptPreviewSheetState();
}

/// Reçu — cadre unique avec sections EXPÉDITEUR / BÉNÉFICIAIRE / CONTENU
/// séparées par des filets pleins, à l'image du modèle papier de référence
/// (numéro en évidence, champs alignés label/valeur).
class _ReceiptBox extends StatelessWidget {
  final Colis colis;
  final String? agentName;
  const _ReceiptBox({required this.colis, this.agentName});

  @override
  Widget build(BuildContext context) {
    final ref = colisReceiptNumber(colis);
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.black87, width: 1.4),
        borderRadius: BorderRadius.circular(4),
      ),
      child: DefaultTextStyle(
        // Tout le texte du reçu en gras (demande explicite) — les styles
        // explicites ci-dessous (ex. couleur grise des libellés) ne
        // redéfinissent volontairement pas fontWeight : ils héritent donc
        // tous de ce gras ambiant (voir _Field, qui ne fixe que la couleur).
        style: const TextStyle(
          fontFamily: 'monospace',
          fontSize: 12,
          height: 1.4,
          color: Colors.black87,
          fontWeight: FontWeight.bold,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
              child: Column(
                children: [
                  Text(colis.companyName.isNotEmpty ? colis.companyName : 'TIBUS COURRIER',
                      textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  // Téléphone du SIÈGE (compagnie) sous le nom de la
                  // compagnie, et téléphone de la gare de destination juste
                  // en dessous. Le téléphone de la gare de DÉPART est lui
                  // affiché dans le bloc EXPÉDITEUR (voir _Field
                  // 'Tél. agence' plus bas).
                  if (colis.companyPhone.isNotEmpty)
                    Text('Tél siège: ${colis.companyPhone}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                  if (colis.gareDestinationPhone.isNotEmpty)
                    Text('Tél dest: ${colis.gareDestinationPhone}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                  const Text('Reçu expédition colis', textAlign: TextAlign.center, style: TextStyle(fontSize: 11)),
                ],
              ),
            ),
            if (colis.isPendingSync)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  border: Border.all(color: Colors.orange.shade300),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'REÇU PROVISOIRE — enregistré hors connexion, sera confirmé à la synchronisation.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.deepOrange),
                ),
              ),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 12),
              padding: const EdgeInsets.symmetric(vertical: 6),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.black45),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text('N°   $ref',
                  textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ),
            _Section(
              title: 'EXPÉDITEUR',
              children: [
                Text(colis.nomExpediteur, style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                _Field('Téléphone', colis.telephoneExpediteur),
                _Field("Frais d'envoi", '${colis.montantFret.toStringAsFixed(0)} FCFA'),
                if (colis.valeurMarchandise != null && colis.valeurMarchandise! > 0)
                  _Field('Valeur', '${colis.valeurMarchandise!.toStringAsFixed(0)} FCFA'),
                _Field('Agence', colis.gareDepart),
                if (colis.gareDepartPhone.isNotEmpty) _Field('Tél. agence', colis.gareDepartPhone),
                if (agentName != null) _Field('Agent', agentName!),
                _Field('Déposé le', formatColisDate(colis.createdAt)),
              ],
            ),
            _Section(
              title: 'BÉNÉFICIAIRE',
              children: [
                Text(colis.nomDestinataire, style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                _Field('Téléphone', colis.telephoneDestinataire),
                _Field('Destination', colis.gareDestination),
                // Tél. destination déplacé en en-tête (voir plus haut).
              ],
            ),
            _Section(
              title: 'CONTENU',
              isLast: true,
              children: [
                _Field('Nature du colis', colisNatureLabel(colis)),
                _Field('Description', colisDescriptionLabel(colis)),
                if (colis.poidsKg != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text('Poids : ${colis.poidsKg} kg', style: const TextStyle(fontSize: 11, color: Colors.black54)),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Column(
                children: [
                  const Divider(height: 16),
                  const Text(
                    'Retrait sous 72h - passé ce délai, des frais de\nmagasinage sont imputables.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                  // Pas de QR sur le reçu — ni à l'impression (voir
                  // printer_service.dart / P3PrinterModule.kt), ni dans cet
                  // aperçu : l'aperçu doit refléter le rendu papier. Le QR
                  // reste sur le TALON uniquement (voir _TalonBox).
                  const SizedBox(height: 6),
                  const Text('Powered by Tibus', textAlign: TextAlign.center, style: TextStyle(fontSize: 10, color: Colors.black54)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final List<Widget> children;
  final bool isLast;
  const _Section({required this.title, required this.children, this.isLast = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(
        border: Border(
          top: const BorderSide(color: Colors.black45, width: 1),
          bottom: isLast ? BorderSide.none : const BorderSide(color: Colors.black12, width: 0.6),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 0.5)),
          const SizedBox(height: 4),
          ...children,
        ],
      ),
    );
  }
}

class _Field extends StatelessWidget {
  final String label;
  final String value;
  const _Field(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 100, child: Text(label, style: const TextStyle(color: Colors.black54))),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

/// Talon — étiquette compacte à détacher et coller sur le colis : référence
/// + QR en évidence, destination et montant en gros, destinataire, puis
/// expéditeur en petit (repris du modèle papier de référence).
class _TalonBox extends StatelessWidget {
  final Colis colis;
  const _TalonBox({required this.colis});

  @override
  Widget build(BuildContext context) {
    final ref = colisReceiptNumber(colis);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.black87, width: 1.4),
        borderRadius: BorderRadius.circular(4),
      ),
      child: DefaultTextStyle(
        style: const TextStyle(fontFamily: 'monospace', fontSize: 12, height: 1.3, color: Colors.black87),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(colis.companyName.isNotEmpty ? colis.companyName : 'TIBUS COURRIER',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
            // Même en-tête que le reçu (voir _ReceiptBox) : téléphone du
            // siège (compagnie) et de la gare de destination, en gras, puis
            // sous-titre explicite. Le téléphone de la gare de départ est
            // lui affiché plus bas, dans le bloc expédition.
            if (colis.companyPhone.isNotEmpty)
              Text('Tél siège: ${colis.companyPhone}',
                  style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold)),
            if (colis.gareDestinationPhone.isNotEmpty)
              Text('Tél dest: ${colis.gareDestinationPhone}',
                  style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold)),
            const Text('Reçu expédition colis', style: TextStyle(fontSize: 9)),
            if (colis.isPendingSync)
              const Text('*** PROVISOIRE ***',
                  style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.deepOrange)),
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    decoration: BoxDecoration(border: Border.all(color: Colors.black45), borderRadius: BorderRadius.circular(4)),
                    child: Text(ref, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  ),
                ),
                const SizedBox(width: 10),
                QrImageView(data: colis.id, size: 56),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(colis.gareDestination.toUpperCase(),
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                ),
                Text('${colis.montantFret.toStringAsFixed(0)} FCFA', style: const TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 6),
            Text(colis.nomDestinataire, style: const TextStyle(fontWeight: FontWeight.w600)),
            Text(colis.telephoneDestinataire),
            const SizedBox(height: 6),
            Text('Expéditeur : ${colis.nomExpediteur}', style: const TextStyle(fontSize: 10, color: Colors.black54)),
            Text(colis.telephoneExpediteur, style: const TextStyle(fontSize: 10, color: Colors.black54)),
            // Bloc expédition : agence de départ + son téléphone (déplacé
            // depuis l'en-tête, voir plus haut).
            Text('Agence : ${colis.gareDepart}', style: const TextStyle(fontSize: 10, color: Colors.black54)),
            if (colis.gareDepartPhone.isNotEmpty)
              Text('Tél. agence : ${colis.gareDepartPhone}',
                  style: const TextStyle(fontSize: 10, color: Colors.black54)),
          ],
        ),
      ),
    );
  }
}

/// Sélecteur d'imprimante USB/Bluetooth réelle (Xprinter XP-Q200, Mini
/// Printer MPT-II…) : scan, tap sur un appareil trouvé -> connexion +
/// impression directe (reçu + talon). Pont dédié
/// (esc_pos_printer_service.dart), distinct de la P3 intégrée et du pont
/// desktop WisePrinter ci-dessus.
class _EscPosPrinterSheet extends ConsumerStatefulWidget {
  final Colis colis;
  final String? agentName;
  const _EscPosPrinterSheet({required this.colis, this.agentName});

  @override
  ConsumerState<_EscPosPrinterSheet> createState() => _EscPosPrinterSheetState();
}

class _EscPosPrinterSheetState extends ConsumerState<_EscPosPrinterSheet> {
  StreamSubscription<PrinterDevice>? _sub;
  final List<PrinterDevice> _usbDevices = [];
  final List<PrinterDevice> _btDevices = [];
  final _ipCtrl = TextEditingController();
  bool _scanningUsb = false;
  bool _scanningBt = false;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Pré-remplit avec la dernière IP réseau utilisée (YHD-8390, etc.).
    ref.read(printerServiceProvider).escPos.lastNetworkIp().then((ip) {
      if (mounted && ip != null && ip.isNotEmpty && _ipCtrl.text.isEmpty) {
        setState(() => _ipCtrl.text = ip);
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _ipCtrl.dispose();
    super.dispose();
  }

  /// Impression réseau LAN/WiFi (TCP 9100) — ex. YHD-8390. L'IP est celle du
  /// ticket d'auto-test de l'imprimante (maintenir FEED à l'allumage).
  Future<void> _printOnNetwork() async {
    final ip = _ipCtrl.text.trim();
    if (ip.isEmpty) {
      setState(() => _error = "Saisissez l'adresse IP de l'imprimante (ticket d'auto-test).");
      return;
    }
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final escPos = ref.read(printerServiceProvider).escPos;
    try {
      await escPos.connectNetwork(ip);
      await escPos.printColisReceiptWithTalon(
        widget.colis,
        type: PrinterType.network,
        agentName: widget.agentName,
      );
      await escPos.saveNetworkIp(ip);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() => _error =
            'Impression réseau impossible ($ip) : $e — vérifiez que l\'imprimante est sur le même réseau WiFi/LAN.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _scan(PrinterType type) {
    _sub?.cancel();
    setState(() {
      _error = null;
      if (type == PrinterType.usb) {
        _usbDevices.clear();
        _scanningUsb = true;
      } else {
        _btDevices.clear();
        _scanningBt = true;
      }
    });
    final escPos = ref.read(printerServiceProvider).escPos;
    final stream = type == PrinterType.usb ? escPos.discoverUsb() : escPos.discoverBluetooth();
    _sub = stream.listen(
      (device) {
        if (!mounted) return;
        setState(() {
          if (type == PrinterType.usb) {
            _usbDevices.add(device);
          } else {
            _btDevices.add(device);
          }
        });
      },
      onError: (e) {
        if (!mounted) return;
        setState(() {
          _error = '$e';
          _scanningUsb = false;
          _scanningBt = false;
        });
      },
      onDone: () {
        if (!mounted) return;
        setState(() {
          _scanningUsb = false;
          _scanningBt = false;
        });
      },
    );
    // La découverte (surtout Bluetooth) ne se termine pas toujours d'elle-
    // même : on borne la recherche pour ne pas laisser le spinner tourner.
    Future.delayed(const Duration(seconds: 4), () {
      _sub?.cancel();
      if (!mounted) return;
      setState(() {
        _scanningUsb = false;
        _scanningBt = false;
      });
    });
  }

  Future<void> _printOn(PrinterDevice device, PrinterType type) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final escPos = ref.read(printerServiceProvider).escPos;
    try {
      if (type == PrinterType.usb) {
        await escPos.connectUsb(device);
      } else {
        await escPos.connectBluetooth(device);
      }
      await escPos.printColisReceiptWithTalon(widget.colis, type: type, agentName: widget.agentName);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) setState(() => _error = 'Impression impossible : $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _deviceList(List<PrinterDevice> devices, bool scanning, IconData icon, PrinterType type) {
    if (devices.isEmpty && !scanning) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 4),
        child: Text('Aucune imprimante trouvée.', style: TextStyle(color: Colors.grey, fontSize: 12)),
      );
    }
    return Column(
      children: devices
          .map((d) => ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(icon),
                title: Text(d.name?.isNotEmpty == true ? d.name! : 'Imprimante'),
                onTap: _busy ? null : () => _printOn(d, type),
              ))
          .toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text('Imprimante USB / Bluetooth / Réseau',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ),
                IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.of(context).pop()),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 4),
              Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 12)),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                const Expanded(
                  child: Text('USB (ex: Xprinter XP-Q200)', style: TextStyle(fontWeight: FontWeight.w600)),
                ),
                TextButton.icon(
                  onPressed: _busy || _scanningUsb ? null : () => _scan(PrinterType.usb),
                  icon: _scanningUsb
                      ? const SizedBox(
                          width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.search, size: 18),
                  label: const Text('Rechercher'),
                ),
              ],
            ),
            _deviceList(_usbDevices, _scanningUsb, Icons.usb, PrinterType.usb),
            const Divider(),
            Row(
              children: [
                const Expanded(
                  child: Text('Bluetooth (ex: Mini Printer MPT-II)',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                ),
                TextButton.icon(
                  onPressed: _busy || _scanningBt ? null : () => _scan(PrinterType.bluetooth),
                  icon: _scanningBt
                      ? const SizedBox(
                          width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.search, size: 18),
                  label: const Text('Rechercher'),
                ),
              ],
            ),
            _deviceList(_btDevices, _scanningBt, Icons.bluetooth, PrinterType.bluetooth),
            const Divider(),
            const Text('Réseau LAN / WiFi (ex: YHD-8390, port 9100)',
                style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            const Text(
              "IP affichée sur le ticket d'auto-test de l'imprimante (maintenir FEED à l'allumage).",
              style: TextStyle(fontSize: 11, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _ipCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Adresse IP',
                      hintText: '192.168.1.87',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: _busy ? null : _printOnNetwork,
                  icon: _busy
                      ? const SizedBox(
                          width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.wifi, size: 18),
                  label: const Text('Imprimer'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PrinterButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool enabled;
  final String? disabledHint;
  final VoidCallback onPressed;

  const _PrinterButton({
    required this.icon,
    required this.label,
    required this.enabled,
    required this.onPressed,
    this.disabledHint,
  });

  @override
  Widget build(BuildContext context) {
    final button = SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        icon: Icon(icon, size: 18),
        label: Align(alignment: Alignment.centerLeft, child: Text(label)),
        onPressed: enabled ? onPressed : null,
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      ),
    );
    if (enabled || disabledHint == null) return button;
    return Tooltip(message: disabledHint!, child: button);
  }
}
