import '../../data/models/colis.dart';

/// Lignes génériques du reçu colis au format {text, align, bold, size} —
/// partagées par tous les ponts d'impression qui ne connaissent pas la
/// structure label/valeur du pont P3 natif (voir printer_service.dart) :
/// pont WisePrinter desktop (window.WisePrinter) et pont ESC/POS USB/
/// Bluetooth (esc_pos_printer_service.dart). Même structure que
/// buildColisReceiptLines() côté web (src/lib/colis-receipt.ts).
List<Map<String, dynamic>> colisReceiptLines(Colis colis) => [
      {'text': 'Reçu expédition colis', 'align': 'center', 'size': 'small'},
      {'text': ''},
      {
        'text': 'Ref: ${colis.id.substring(0, 8).toUpperCase()}',
        'align': 'center',
        'bold': true,
        'size': 'large',
      },
      {'text': 'Statut: ${colis.statut.label}'},
      {'text': ''},
      {'text': 'Expéditeur', 'bold': true},
      {'text': colis.nomExpediteur},
      {'text': colis.telephoneExpediteur, 'size': 'small'},
      {'text': ''},
      {'text': 'Destinataire', 'bold': true},
      {'text': colis.nomDestinataire},
      {'text': colis.telephoneDestinataire, 'size': 'small'},
      {'text': ''},
      {'text': 'Trajet: ${colis.gareDepart} -> ${colis.gareDestination}', 'bold': true},
      if (colis.poidsKg != null) {'text': 'Poids: ${colis.poidsKg} kg'},
      {'text': ''},
      {'text': 'Montant: ${colis.montantFret.toStringAsFixed(0)} FCFA', 'bold': true},
      if (colis.valeurMarchandise != null && colis.valeurMarchandise! > 0)
        {'text': 'Valeur marchandise: ${colis.valeurMarchandise!.toStringAsFixed(0)} FCFA'},
      if (colis.pourcentagePercu != null && colis.pourcentagePercu! > 0)
        {'text': 'Pourcentage perçu: ${colis.pourcentagePercu} %'},
      {'text': ''},
      {'text': 'Powered by Tibus', 'align': 'center', 'size': 'small'},
    ];
