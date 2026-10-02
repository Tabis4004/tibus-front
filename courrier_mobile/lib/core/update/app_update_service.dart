import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

/// Vérifie au démarrage (et au retour au premier plan) si une version plus
/// récente de l'app est publiée, et affiche un pop-up de mise à jour.
///
/// Le registre des versions (`public.app_versions`, RPC `get_app_update`,
/// migration 215) vit TOUJOURS dans Tibus 1.0, quelle que soit la marque :
/// SIS a sa propre base métier (base.societe-sis.com), mais c'est l'éditeur
/// qui publie les apps et tient donc le registre. D'où ce client dédié,
/// indépendant de `Supabase.instance.client`.
///
/// Règle (calculée côté serveur) :
///   versionCode < min_version_code    -> 'required' : pop-up bloquant
///   versionCode < latest_version_code -> 'optional' : « Plus tard » possible
///
/// Toute erreur (hors ligne, ligne absente pour cette app...) est ignorée :
/// la vérification ne doit jamais empêcher d'utiliser l'app.
class AppUpdateService {
  AppUpdateService._();

  // Tibus 1.0 (kqudaqtydimjclwaihqr) — clé anon publique, protégée par RLS.
  static const _registryUrl = 'https://kqudaqtydimjclwaihqr.supabase.co';
  static const _registryAnonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImtxdWRhcXR5ZGltamNsd2FpaHFyIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODA2MDY1NTMsImV4cCI6MjA5NjE4MjU1M30.7bbUqLqqTDTRG4HIUFVzJdYW0NpJZWyoneUYje2JQVI';

  static SupabaseClient? _registry;
  static bool _dialogOpen = false;
  static DateTime? _lastCheck;
  static const _minInterval = Duration(minutes: 30);

  /// Version ignorée via « Plus tard » pendant cette session (pas de
  /// relance à chaque retour au premier plan pour la même version).
  static int? _snoozedVersion;

  static String? get _platform {
    if (kIsWeb) return null; // le web est toujours à jour au rechargement
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'android';
      case TargetPlatform.iOS:
        return 'ios';
      case TargetPlatform.windows:
        return 'windows';
      default:
        return null;
    }
  }

  static Future<void> check(GlobalKey<NavigatorState> navigatorKey,
      {bool force = false}) async {
    final platform = _platform;
    if (platform == null || _dialogOpen) return;
    final now = DateTime.now();
    if (!force && _lastCheck != null && now.difference(_lastCheck!) < _minInterval) {
      return;
    }
    _lastCheck = now;

    try {
      final info = await PackageInfo.fromPlatform();
      final versionCode = int.tryParse(info.buildNumber) ?? 0;
      if (versionCode <= 0) return;

      _registry ??= SupabaseClient(
        _registryUrl,
        _registryAnonKey,
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );
      final rows = await _registry!.rpc('get_app_update', params: {
        'p_app_id': info.packageName,
        'p_platform': platform,
        'p_version_code': versionCode,
      }).timeout(const Duration(seconds: 10));

      if (rows is! List || rows.isEmpty) return;
      final row = Map<String, dynamic>.from(rows.first as Map);
      final status = row['update_status'] as String?;
      if (status != 'optional' && status != 'required') return;

      final latest = (row['latest_version_code'] as num?)?.toInt();
      final isRequired = status == 'required';
      if (!isRequired && latest != null && latest == _snoozedVersion) return;

      final context = navigatorKey.currentContext;
      if (context == null || !context.mounted) return;
      await _showDialog(
        context,
        isRequired: isRequired,
        currentName: info.version,
        latestName: row['latest_version_name'] as String?,
        message: row['message'] as String?,
        storeUrl: row['store_url'] as String?,
        latestCode: latest,
      );
    } catch (e) {
      debugPrint('AppUpdateService: vérification ignorée ($e)');
    }
  }

  static Future<void> _showDialog(
    BuildContext context, {
    required bool isRequired,
    required String currentName,
    String? latestName,
    String? message,
    String? storeUrl,
    int? latestCode,
  }) async {
    _dialogOpen = true;
    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: !isRequired,
        builder: (ctx) => PopScope(
          canPop: !isRequired,
          child: AlertDialog(
            icon: const Icon(Icons.system_update, size: 40),
            title: Text(isRequired
                ? 'Mise à jour obligatoire'
                : 'Mise à jour disponible'),
            content: Text([
              if (message != null && message.trim().isNotEmpty)
                message.trim()
              else if (isRequired)
                'Cette version de l\'application n\'est plus prise en charge. '
                    'Installez la mise à jour pour continuer à l\'utiliser.'
              else
                'Une nouvelle version de l\'application est disponible. '
                    'Nous vous recommandons de l\'installer.',
              '',
              'Version installée : $currentName'
                  '${latestName != null ? '\nNouvelle version : $latestName' : ''}',
            ].join('\n')),
            actions: [
              if (!isRequired)
                TextButton(
                  onPressed: () {
                    _snoozedVersion = latestCode;
                    Navigator.of(ctx).pop();
                  },
                  child: const Text('Plus tard'),
                ),
              FilledButton(
                onPressed: storeUrl == null
                    ? null
                    : () => launchUrl(Uri.parse(storeUrl),
                        mode: LaunchMode.externalApplication),
                child: const Text('Mettre à jour'),
              ),
            ],
          ),
        ),
      );
    } finally {
      _dialogOpen = false;
    }
  }
}
