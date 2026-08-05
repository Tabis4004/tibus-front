import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_service.dart';

/// Canal de contact plateforme (WhatsApp + email) pour l'onglet Support de
/// l'app agent — réutilise get_contact_options, déjà utilisée côté web par
/// la page "Contact" publique (SupabaseContactPage.tsx) et configurée par le
/// superadmin dans l'onglet "Contact" du Panneau Admin
/// (ContactSettingsPanel.tsx, scope "platform"). Une seule config pour toute
/// la plateforme, pas par compagnie — c'est le scope demandé pour le
/// support agent.
class SupportContact {
  final String? whatsappNumber;
  final String? supportEmail;

  const SupportContact({this.whatsappNumber, this.supportEmail});

  factory SupportContact.fromMap(Map<String, dynamic> map) => SupportContact(
        whatsappNumber: (map['platformWhatsapp'] as String?)?.trim().isEmpty == true
            ? null
            : map['platformWhatsapp'] as String?,
        supportEmail: (map['platformNotificationEmail'] as String?)?.trim().isEmpty == true
            ? null
            : map['platformNotificationEmail'] as String?,
      );

  bool get hasWhatsapp => whatsappNumber != null && whatsappNumber!.trim().isNotEmpty;
  bool get hasEmail => supportEmail != null && supportEmail!.trim().isNotEmpty;
}

class SupportService {
  final SupabaseClient _client = SupabaseService.client;

  Future<SupportContact> getPlatformContact() async {
    final data = await _client.rpc('get_contact_options');
    return SupportContact.fromMap((data ?? {}) as Map<String, dynamic>);
  }
}
