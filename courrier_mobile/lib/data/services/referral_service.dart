import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_service.dart';

const _kReferralCodeKey = 'courrier-referral-code';

/// Parrainage — conservé comme outil marketing (croissance organique).
/// Reprend la même logique que ReferralBootstrap.tsx côté web :
/// on capture un code de parrainage (ex: lien de partage), on le stocke
/// localement, puis on le "réclame" une fois l'utilisateur connecté.
class ReferralService {
  final SupabaseClient _client = SupabaseService.client;

  Future<void> storeReferralCode(String code) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kReferralCodeKey, code);
  }

  Future<String?> readStoredReferralCode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kReferralCodeKey);
  }

  Future<void> clearStoredReferralCode() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kReferralCodeKey);
  }

  Future<Map<String, dynamic>> claimReferralSignup(String code) async {
    final data = await _client.rpc('claim_referral_signup', params: {'p_code': code});
    return (data ?? {}) as Map<String, dynamic>;
  }
}
