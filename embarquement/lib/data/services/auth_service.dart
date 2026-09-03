import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_service.dart';
import '../models/app_role.dart';

/// Auth réutilisant les comptes Tibus existants (même projet Supabase) —
/// pas de signup ni de nouveau système de comptes : un agent qui a déjà un
/// compte Tibus (owner/controleur/vendeur/chauffeur/super_admin) se connecte
/// ici avec les mêmes identifiants. Voir plan_module_embarquement_v2.md §6.
class AuthService {
  final SupabaseClient _client = SupabaseService.client;

  Session? get currentSession => _client.auth.currentSession;
  bool get isLoggedIn => currentSession != null;
  Stream<AuthState> get onAuthStateChange => _client.auth.onAuthStateChange;

  Future<AuthResponse> signInWithPassword({
    required String identifier,
    required String password,
  }) {
    return _client.auth.signInWithPassword(email: identifier, password: password);
  }

  Future<void> signOut() => _client.auth.signOut();

  Future<void> requestPasswordReset(String email) {
    return _client.auth.resetPasswordForEmail(email.trim());
  }

  /// Rôles de l'utilisateur connecté (une entrée par compagnie affectée) —
  /// même requête que courrier_mobile/lib/data/services/auth_service.dart
  /// (fetchMyRoles), portée volontairement identique pour rester cohérent
  /// avec le reste de l'app Tibus.
  Future<List<AppRole>> fetchMyRoles() async {
    final authUserId = currentSession?.user.id;
    if (authUserId == null) return [];

    final appUser = await _client
        .from('Users')
        .select('id')
        .eq('auth_user_id', authUserId)
        .maybeSingle();
    final appUserId = appUser?['id'] as String?;
    if (appUserId == null) return [];

    final rows = await _client
        .from('UserRoles')
        .select('roleId, companyId, Role(name, scope, level, droits), Companies(name)')
        .eq('userId', appUserId);

    return (rows as List).map((row) {
      final role = row['Role'] as Map<String, dynamic>? ?? {};
      final company = row['Companies'] as Map<String, dynamic>? ?? {};
      return AppRole.fromMap({
        'roleId': row['roleId'],
        'companyId': row['companyId'],
        'roleName': role['name'],
        'scope': role['scope'],
        'level': role['level'],
        'droits': role['droits'],
        'companyName': company['name'],
      });
    }).toList();
  }
}
