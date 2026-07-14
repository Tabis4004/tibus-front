import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/config/env.dart';

/// Backend Tibus principal — utilisé UNIQUEMENT pour le suivi de colis
/// (mêmes RPC que courrier_mobile : `resolve_colis_retrait_code`,
/// `get_colis_autonome_detail`). Aucune authentification nécessaire ici :
/// le suivi par code fonctionne sans compte, exactement comme sur Courrier
/// agent. Client Supabase "principal" (singleton `Supabase.instance`).
class TibusBackend {
  TibusBackend._();

  static Future<void> init() async {
    await Supabase.initialize(
      url: Env.tibusSupabaseUrl,
      anonKey: Env.tibusSupabaseAnonKey,
    );
  }

  static SupabaseClient get client => Supabase.instance.client;

  static Future<Map<String, dynamic>?> lookupColisByCode(String code) async {
    final colisId = await client.rpc('resolve_colis_retrait_code', params: {'p_code': code});
    if (colisId == null) return null;
    final detail = await client.rpc('get_colis_autonome_detail', params: {'p_colis_id': colisId});
    return detail as Map<String, dynamic>?;
  }
}
