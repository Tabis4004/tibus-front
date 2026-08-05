import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/mailto.dart';
import '../../../core/utils/whatsapp.dart';
import '../../../data/services/support_service.dart';

/// Onglet Support de l'app agent — trois canaux, demande explicite :
/// 1. Réponses in-app (FAQ statique, ci-dessous) — pas d'attente, pas de
///    réseau requis.
/// 2. Formulaire de contact -> "ticket" envoyé par email (mailto, comme le
///    reste de l'app — voir mailto.dart — aucune dépendance serveur : c'est
///    la boîte mail de destination qui fait office de suivi de tickets).
/// 3. Bouton WhatsApp, numéro configuré côté Tibus pour toute la plateforme
///    (pas par compagnie) — réutilise get_contact_options / scope
///    "platform", déjà utilisée par la page Contact publique du web
///    (SupabaseContactPage.tsx) et configurée par le superadmin dans
///    l'onglet "Contact" du Panneau Admin (ContactSettingsPanel.tsx).
class SupportScreen extends ConsumerStatefulWidget {
  const SupportScreen({super.key});

  @override
  ConsumerState<SupportScreen> createState() => _SupportScreenState();
}

class _SupportScreenState extends ConsumerState<SupportScreen> {
  late Future<SupportContact> _contactFuture;
  final _messageCtrl = TextEditingController();
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _contactFuture = ref.read(supportServiceProvider).getPlatformContact();
  }

  @override
  void dispose() {
    _messageCtrl.dispose();
    super.dispose();
  }

  String _outboundMessage() {
    final contact = ref.read(myContactProvider).valueOrNull;
    final roles = ref.read(myRolesProvider).valueOrNull ?? const [];
    final companyName = roles.isNotEmpty ? (roles.first.companyName ?? '') : '';
    final lines = <String>[
      'Bonjour, je vous contacte depuis l\'app agent Tibus Courrier.',
      if (contact?.email != null && contact!.email!.isNotEmpty) 'Compte : ${contact.email}',
      if (contact?.phone != null && contact!.phone!.isNotEmpty) 'Téléphone : ${contact.phone}',
      if (companyName.isNotEmpty) 'Compagnie : $companyName',
      '',
      _messageCtrl.text.trim(),
    ];
    return lines.join('\n');
  }

  Future<void> _sendWhatsApp(String number) async {
    if (_messageCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Décrivez votre problème avant d\'envoyer.')),
      );
      return;
    }
    setState(() => _sending = true);
    try {
      final ok = await openWhatsApp(number, _outboundMessage());
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Impossible d\'ouvrir WhatsApp sur cet appareil.')),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _sendEmail(String email) async {
    if (_messageCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Décrivez votre problème avant d\'envoyer.')),
      );
      return;
    }
    setState(() => _sending = true);
    try {
      final ok = await openMailto(
        email,
        subject: 'Support Tibus Courrier — demande agent',
        body: _outboundMessage(),
      );
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Aucune app mail configurée sur cet appareil.')),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Support')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Questions fréquentes', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const _SupportFaq(),
          const SizedBox(height: 24),
          const Text('Nous contacter', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          const Text(
            'Décrivez votre problème, puis choisissez WhatsApp ou email — votre compte et votre compagnie sont joints automatiquement.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _messageCtrl,
            maxLines: 5,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: 'Ex : le talon ne s\'imprime plus depuis ce matin...',
            ),
          ),
          const SizedBox(height: 12),
          FutureBuilder<SupportContact>(
            future: _contactFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              final contact = snapshot.data ?? const SupportContact();
              if (!contact.hasWhatsapp && !contact.hasEmail) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'Aucun canal de support configuré pour le moment.',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                );
              }
              return Column(
                children: [
                  if (contact.hasWhatsapp)
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF25D366),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        icon: const Icon(Icons.chat_outlined),
                        label: const Text('Discuter sur WhatsApp'),
                        onPressed: _sending ? null : () => _sendWhatsApp(contact.whatsappNumber!),
                      ),
                    ),
                  if (contact.hasWhatsapp && contact.hasEmail) const SizedBox(height: 10),
                  if (contact.hasEmail)
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                        icon: const Icon(Icons.email_outlined),
                        label: const Text('Envoyer par email'),
                        onPressed: _sending ? null : () => _sendEmail(contact.supportEmail!),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _SupportFaq extends StatelessWidget {
  const _SupportFaq();

  static const _items = <(String, String)>[
    (
      'Un colis reste "en attente de synchronisation", que faire ?',
      'Il a été enregistré hors connexion (voir le bandeau orange sur l\'accueil). Dès que le téléphone retrouve une connexion internet, la synchronisation se relance automatiquement — le numéro définitif remplace alors la référence provisoire. Inutile de le ressaisir.',
    ),
    (
      'Comment imprimer à nouveau le reçu ou le talon d\'un colis ?',
      'Ouvrez le colis depuis "Manifeste colis" ou "Colis récents", puis utilisez le bouton d\'impression sur sa fiche de détail — vous pouvez le réimprimer autant de fois que nécessaire.',
    ),
    (
      'Le talon se colle mal, le scotch efface du texte : normal ?',
      'Non — signalez-le en support, avec le modèle d\'imprimante utilisé. Ce point a déjà été corrigé pour l\'imprimante Bluetooth YHD (marges + emplacement du bloc expéditeur).',
    ),
    (
      'Pourquoi certains champs (montant, valeur) n\'apparaissent pas sur mes rapports ?',
      'Le propriétaire de votre compagnie peut masquer certaines données sensibles par rapport (Journal de vente, Bordereau...) depuis le web, page "Colis autonomes". Ce n\'est pas un bug — demandez-lui si un champ manquant vous semble nécessaire.',
    ),
    (
      'Comment ouvrir ou clôturer ma caisse du guichet ?',
      'Depuis "Ma caisse" sur l\'accueil : renseignez le fond de roulement à l\'ouverture, puis utilisez "Clôturer la session" en fin de journée pour imprimer le journal de vente et remettre les espèces.',
    ),
    (
      'J\'ai enregistré un colis avec une erreur (destinataire, montant...) : je fais comment ?',
      'Contactez votre gérant de gare ou le support — la correction/l\'annulation d\'un colis déjà enregistré nécessite un rôle superviseur, un simple agent ne peut pas modifier une fiche déjà créée.',
    ),
    (
      'L\'application fonctionne-t-elle sans connexion internet ?',
      'Oui pour l\'enregistrement de colis (mode hors-ligne avec file d\'attente) — la plupart des autres écrans (rapports, stats, scan de lots) nécessitent une connexion active.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Column(
        children: [
          for (final (question, answer) in _items)
            ExpansionTile(
              title: Text(question, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              expandedCrossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(answer, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.4)),
              ],
            ),
        ],
      ),
    );
  }
}
