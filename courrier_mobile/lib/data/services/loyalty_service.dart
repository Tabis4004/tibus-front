import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_service.dart';
import '../models/loyalty.dart';

/// Fidélité — conservée pour vulgariser l'app (levier marketing).
/// Réutilise get_traveler_loyalty_context / validate_loyalty_redemption,
/// déjà utilisées côté "voyageur" dans Tibus. À adapter côté base pour que
/// l'achat d'un envoi colis crédite des points au même titre qu'un billet
/// (voir README, section Dette technique).
class LoyaltyService {
  final SupabaseClient _client = SupabaseService.client;

  Future<LoyaltyContext> getMyLoyaltyContext(String userId) async {
    final data = await _client.rpc('get_traveler_loyalty_context', params: {'p_user_id': userId});
    return LoyaltyContext.fromMap((data ?? {}) as Map<String, dynamic>);
  }

  Future<Map<String, dynamic>> validateRedemption({
    required String userId,
    required int points,
  }) async {
    final data = await _client.rpc('validate_loyalty_redemption', params: {
      'p_user_id': userId,
      'p_points': points,
    });
    return (data ?? {}) as Map<String, dynamic>;
  }
}
