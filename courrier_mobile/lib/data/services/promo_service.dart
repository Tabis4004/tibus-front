import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_service.dart';
import '../models/loyalty.dart';

/// Codes promo — conservés comme outil marketing.
/// `list_owner_promo_codes` est aujourd'hui scopée "owner" (gestion des
/// codes par la compagnie), pas "client" (application d'un code à l'achat).
/// Une RPC cliente de validation/application d'un code sur un colis reste
/// à ajouter côté base (voir README, section Dette technique) : Courrier
/// prévoit déjà l'écran et l'appel, prêt à être branché.
class PromoService {
  final SupabaseClient _client = SupabaseService.client;

  Future<List<PromoCode>> listCompanyPromoCodes() async {
    final data = await _client.rpc('list_owner_promo_codes');
    return (data as List).map((e) => PromoCode.fromMap(e as Map<String, dynamic>)).toList();
  }

  /// Placeholder — à remplacer par la RPC cliente une fois ajoutée côté base.
  Future<bool> applyPromoCodeToColis({required String code, required String colisId}) async {
    throw UnimplementedError(
      'RPC d\'application client d\'un code promo à ajouter côté Supabase '
      '(ex: apply_promo_code_to_colis).',
    );
  }
}
