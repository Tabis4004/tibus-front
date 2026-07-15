import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/config/env.dart';

/// Résultat d'une inscription — miroir de SignUpOutcome côté courrier_mobile
/// (data/services/auth_service.dart).
class SignUpOutcome {
  final User? user;
  final Session? session;
  final bool requiresConfirmation;

  const SignUpOutcome({required this.user, required this.session, required this.requiresConfirmation});
}

/// Backend Tibus principal — suivi de colis (mêmes RPC que courrier_mobile :
/// `resolve_colis_retrait_code`, `get_colis_autonome_detail`, fonctionnent
/// sans compte) ET authentification "client" (expéditeur/destinataire) :
/// le compte créé/utilisé ici EST le compte Tibus ("compte Tibus Africa")
/// qui identifie la personne avant de commander une livraison — voir
/// RideBackend.ensureMirroredSession, qui en dérive un compte miroir sur le
/// projet Ride séparé plutôt que de s'appuyer sur l'auth anonyme (désactivée
/// côté projet Ride, et de toute façon inadaptée : la personne qui commande
/// n'est pas un inconnu, elle est déjà identifiée ici).
///
/// Logique d'inscription reprise à l'identique de courrier_mobile
/// (AuthService.signUpWithPassword + _ensureUserProfile) : MÊME projet
/// Supabase (kqudaqtydimjclwaihqr), donc un compte créé sur courrier_mobile
/// (agent, écran "Créer un compte" côté client) fonctionne aussi ici, et
/// réciproquement. Client Supabase "principal" (singleton `Supabase.instance`).
class TibusBackend {
  TibusBackend._();

  static Future<void> init() async {
    await Supabase.initialize(
      url: Env.tibusSupabaseUrl,
      anonKey: Env.tibusSupabaseAnonKey,
    );
  }

  static SupabaseClient get client => Supabase.instance.client;

  static User? get currentUser => client.auth.currentUser;
  static bool get isLoggedIn => currentUser != null;
  static Stream<AuthState> get onAuthStateChange => client.auth.onAuthStateChange;

  static Future<AuthResponse> signIn({required String identifier, required String password}) {
    return client.auth.signInWithPassword(email: identifier, password: password);
  }

  static Future<void> signOut() => client.auth.signOut();

  static Future<void> requestPasswordReset(String email) {
    return client.auth.resetPasswordForEmail(email.trim());
  }

  /// Inscription "client" — crée le compte Supabase Auth, puis — si une
  /// session est immédiatement disponible (pas de confirmation email
  /// requise) — la ligne Users correspondante avec le rôle "traveler".
  static Future<SignUpOutcome> signUp({
    required String email,
    required String password,
    required String fullName,
    required String phone,
  }) async {
    final response = await client.auth.signUp(
      email: email,
      password: password,
      data: {'full_name': fullName.trim(), 'phone': phone.trim()},
    );

    if (response.user != null && response.session != null) {
      await _ensureUserProfile(response.user!, fallbackPhone: phone);
    }

    return SignUpOutcome(
      user: response.user,
      session: response.session,
      requiresConfirmation: response.session == null,
    );
  }

  /// Miroir de ensureUserProfile (courrier_mobile/auth_service.dart) : crée
  /// la ligne Users + rôle "traveler" si elle n'existe pas encore pour ce
  /// compte Auth. Idempotent.
  static Future<void> _ensureUserProfile(User authUser, {String? fallbackPhone}) async {
    final existing = await client.from('Users').select('id').eq('auth_user_id', authUser.id).maybeSingle();
    if (existing != null) return;

    final countries = await client.from('Countries').select('id').limit(1);
    if ((countries as List).isEmpty) {
      throw Exception("Aucun pays en base. Impossible de créer le profil (voir table Countries).");
    }

    final meta = authUser.userMetadata ?? {};
    final fullName = (meta['full_name'] as String?) ?? (meta['name'] as String?) ?? '';
    final parts = fullName.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    final firstName = parts.isNotEmpty ? parts.first : 'Utilisateur';
    final lastName = parts.length > 1 ? parts.sublist(1).join(' ') : 'Tibus';

    final email = authUser.email ?? '';
    final base = email.split('@').first.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_');
    final username = '${base.isEmpty ? 'user' : base}_${authUser.id.substring(0, 6)}'.toLowerCase();

    final phone = ((meta['phone'] as String?) ?? authUser.phone ?? fallbackPhone ?? '').trim();
    final profileCompleted = phone.replaceAll(RegExp(r'\D'), '').length >= 9 &&
        !(firstName == 'Utilisateur' && lastName == 'Tibus');

    final profile = await client
        .from('Users')
        .insert({
          'auth_user_id': authUser.id,
          'firstName': firstName,
          'lastName': lastName,
          'username': username,
          'email': email.isEmpty ? null : email,
          'phone': phone.isEmpty ? null : phone,
          'countryId': countries.first['id'],
          'profileCompleted': profileCompleted,
        })
        .select('id')
        .single();

    final travelerRole = await client.from('Role').select('id').eq('name', 'traveler').single();

    await client.from('UserRoles').insert({
      'userId': profile['id'],
      'roleId': travelerRole['id'],
      'companyId': null,
      'countryId': null,
    });
  }

  static Future<Map<String, dynamic>?> lookupColisByCode(String code) async {
    final colisId = await client.rpc('resolve_colis_retrait_code', params: {'p_code': code});
    if (colisId == null) return null;
    final detail = await client.rpc('get_colis_autonome_detail', params: {'p_colis_id': colisId});
    return detail as Map<String, dynamic>?;
  }
}
