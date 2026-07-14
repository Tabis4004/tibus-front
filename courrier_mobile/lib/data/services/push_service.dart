import 'dart:async';
import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_service.dart';
import '../models/colis.dart';

/// Handler de messages FCM reçus en arrière-plan (app fermée/en fond).
/// Doit rester une fonction TOP-LEVEL (pas une méthode de classe) —
/// contrainte de firebase_messaging, appelée dans un isolate séparé.
/// Enregistrée dans main.dart via `FirebaseMessaging.onBackgroundMessage`.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Rien à faire ici : FCM affiche déjà la notification système à partir
  // du payload "notification" envoyé par l'edge function send-colis-push.
  // On garde ce handler pour permettre un traitement data-only plus tard
  // (ex: mise à jour d'un badge, synchro locale) sans changer la signature.
}

/// Notifications de suivi de colis pour le client (expéditeur/destinataire).
///
/// Deux canaux, actifs en parallèle :
/// 1. Supabase Realtime + notification locale : fonctionne dès maintenant,
///    mais seulement pendant que l'app est ouverte au premier plan.
/// 2. FCM (Firebase Cloud Messaging) : notifications reçues même app
///    fermée. Nécessite `flutterfire configure` (génère
///    lib/firebase_options.dart) + l'edge function
///    supabase/functions/send-colis-push (voir README).
class PushService {
  final SupabaseClient _client = SupabaseService.client;
  final FlutterLocalNotificationsPlugin _local = FlutterLocalNotificationsPlugin();
  // Lazy à dessein : FirebaseMessaging.instance appelle Firebase.app() en
  // interne et lève '[core/no-app]' si Firebase.initializeApp() a échoué
  // ou n'est pas encore terminé (voir main.dart). Un champ `final` évalué
  // à la construction ferait planter PushService() de façon non rattrapée
  // dès le premier ref.read(pushServiceProvider) — un getter reporte l'accès
  // à l'intérieur des try/catch de registerForPushNotifications() et
  // unregisterCurrentToken(), qui gèrent déjà ce cas dégradé.
  FirebaseMessaging get _messaging => FirebaseMessaging.instance;
  RealtimeChannel? _channel;
  StreamSubscription<String>? _tokenRefreshSub;
  StreamSubscription<RemoteMessage>? _foregroundSub;
  bool _localNotifReady = false;

  /// Idempotent — appelée automatiquement par watchColis() et
  /// registerForPushNotifications(), inutile de l'appeler à la main.
  Future<void> init() async {
    if (_localNotifReady) return;
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings();
    await _local.initialize(
      const InitializationSettings(android: androidInit, iOS: iosInit),
    );
    _localNotifReady = true;
  }

  // --- Suivi temps réel (Supabase Realtime) — actif sans config externe ---

  /// Écoute les mises à jour de statut d'un colis précis et notifie
  /// l'utilisateur en temps réel (app ouverte).
  void watchColis(String colisId, {required void Function(ColisStatut) onUpdate}) {
    unawaited(init());
    _channel?.unsubscribe();
    _channel = _client
        .channel('colis-$colisId')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          // Nom de table et colonnes RÉELS (snake_case) de colis_autonomes,
          // vérifiés directement sur le projet Supabase Tibus — à ne pas
          // confondre avec le JSON camelCase renvoyé par les RPC
          // (register_colis_autonome, list_colis_autonomes...), qui n'est
          // qu'un alias de présentation et ne reflète pas les colonnes brutes.
          table: 'colis_autonomes',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: colisId,
          ),
          callback: (payload) {
            final raw = payload.newRecord['statut_colis'] as String?;
            if (raw == null) return;
            final statut = ColisStatutX.fromDb(raw);
            onUpdate(statut);
            _notifyLocal(statut);
          },
        )
        .subscribe();
  }

  void stopWatching() {
    _channel?.unsubscribe();
    _channel = null;
  }

  Future<void> _notifyLocal(ColisStatut statut) async {
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'courrier_colis_updates',
        'Suivi de colis',
        importance: Importance.high,
        priority: Priority.high,
      ),
      iOS: DarwinNotificationDetails(),
    );
    await _local.show(
      statut.hashCode,
      'Mise à jour de votre colis',
      'Statut : ${statut.label}',
      details,
    );
  }

  // --- FCM — actif une fois flutterfire configure exécuté ------------------

  /// À appeler après une connexion réussie (ex: dans le routeur, quand
  /// l'utilisateur passe de LoginScreen à AgentShell/TrackColisScreen).
  /// Ne fait rien silencieusement si Firebase n'est pas initialisé —
  /// permet de garder cet appel inconditionnel dans le reste du code.
  Future<void> registerForPushNotifications() async {
    // Pas de FCM configuré pour le web (voir main.dart). On garde
    // uniquement le suivi Realtime sur ce canal (watchColis), qui
    // fonctionne partout, y compris web.
    if (kIsWeb) return;
    await init();
    try {
      final settings = await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      if (settings.authorizationStatus == AuthorizationStatus.denied) return;

      final token = await _messaging.getToken();
      if (token != null) await _registerToken(token);

      _tokenRefreshSub?.cancel();
      _tokenRefreshSub = _messaging.onTokenRefresh.listen(_registerToken);

      _foregroundSub?.cancel();
      _foregroundSub = FirebaseMessaging.onMessage.listen((message) {
        final notif = message.notification;
        if (notif == null) return;
        _local.show(
          message.hashCode,
          notif.title ?? 'Courrier',
          notif.body ?? '',
          const NotificationDetails(
            android: AndroidNotificationDetails(
              'courrier_colis_updates',
              'Suivi de colis',
              importance: Importance.high,
              priority: Priority.high,
            ),
            iOS: DarwinNotificationDetails(),
          ),
        );
      });
    } catch (_) {
      // Firebase non configuré (firebase_options.dart placeholder) —
      // dégradation silencieuse vers le suivi Realtime uniquement.
    }
  }

  Future<void> _registerToken(String token) async {
    try {
      await _client.rpc('register_device_token', params: {
        'p_fcm_token': token,
        'p_platform':
            defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android',
        'p_app_version': null,
      });
    } catch (_) {
      // best-effort : ne bloque jamais le parcours utilisateur.
    }
  }

  Future<void> unregisterCurrentToken() async {
    if (kIsWeb) return;
    try {
      final token = await _messaging.getToken();
      if (token == null) return;
      await _client.rpc('unregister_device_token', params: {'p_fcm_token': token});
    } catch (_) {
      // idem — best-effort.
    }
  }

  void dispose() {
    _tokenRefreshSub?.cancel();
    _foregroundSub?.cancel();
    stopWatching();
  }
}
