import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_service.dart';
import '../models/app_role.dart';

class SignUpOutcome {
  final User? user;
  final Session? session;
  final String? appUserId;
  final bool requiresConfirmation;

  const SignUpOutcome({
    required this.user,
    required this.session,
    required this.appUserId,
    required this.requiresConfirmation,
  });
}

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

  Future<SignUpOutcome> signUpWithPassword({
    required String email,
    required String password,
    required String fullName,
    required String phone,
  }) async {
    final response = await _client.auth.signUp(
      email: email,
      password: password,
      data: {
        'full_name': fullName.trim(),
        'phone': phone.trim(),
      },
    );

    String? appUserId;
    if (response.user != null && response.session != null) {
      appUserId = await _ensureUserProfile(response.user!, fallbackPhone: phone);
    }

    return SignUpOutcome(
      user: response.user,
      session: response.session,
      appUserId: appUserId,
      requiresConfirmation: response.session == null,
    );
  }

  Future<String> _ensureUserProfile(User authUser, {String? fallbackPhone}) async {
    final existing = await _client
        .from('users')
        .select('id')
        .eq('auth_user_id', authUser.id)
        .maybeSingle();
    if (existing != null) return existing['id'] as String;

    final countries = await _client.from('Countries').select('id').limit(1);
    if ((countries as List).isEmpty) {
      throw Exception(
        "Aucun pays en base. Impossible de créer le profil (voir table Countries).",
      );
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

    final profile = await _client
        .from('users')
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

    final travelerRole = await _client.from('Role').select('id').eq('name', 'traveler').single();

    await _client.from('UserRoles').insert({
      'userId': profile['id'],
      'roleId': travelerRole['id'],
      'companyId': null,
      'countryId': null,
    });

    return profile['id'] as String;
  }

  Future<({String? email, String? phone})> fetchMyContact() async {
    final authUser = currentSession?.user;
    if (authUser == null) return (email: null, phone: null);
    final row = await _client
        .from('users')
        .select('email, phone')
        .eq('auth_user_id', authUser.id)
        .maybeSingle();
    final email = (row?['email'] as String?) ?? authUser.email;
    final phone = row?['phone'] as String?;
    return (email: email, phone: phone);
  }

  Future<void> updatePassword(String newPassword) {
    return _client.auth.updateUser(UserAttributes(password: newPassword));
  }

  Future<List<AppRole>> fetchMyRoles() async {
    final authUserId = currentSession?.user.id;
    if (authUserId == null) return [];

    final appUser = await _client
        .from('users')
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