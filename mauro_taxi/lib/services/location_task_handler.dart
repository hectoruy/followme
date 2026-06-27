import 'dart:async';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/app_config.dart';
import '../config/platform_location.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ─────────────────────────────────────────────────────────────────────────────
const String _kActiveSession = 'active_session_id';
const String _kActiveSessionLink = 'active_session_link';

/// Entry point called by the Android foreground service.
/// MUST be a top-level function annotated with @pragma('vm:entry-point').
@pragma('vm:entry-point')
void locationTaskCallback() {
  FlutterForegroundTask.setTaskHandler(LocationTaskHandler());
}

/// Handles GPS updates while the app is in background or foreground.
///
/// Lifecycle:
/// - [onStart]       → called when the service starts; begins GPS stream.
/// - [onRepeatEvent] → called on the configured interval (we use GPS stream,
///                     so this is intentionally idle).
/// - [onDestroy]     → called when service stops.
///                     • If app was killed: prefs still have session ID
///                       → marks Supabase active=false + clears prefs.
///                     • If user pressed Stop: main isolate cleared prefs first
///                       → sessionId is null → no-op. ✓
class LocationTaskHandler extends TaskHandler {
  StreamSubscription<Position>? _positionSub;
  SupabaseClient? _supabase;
  bool _proximityAlertSent = false;

  static const _proximityThresholdM = 50.0; // metres — realistic for phone GPS

  final FlutterLocalNotificationsPlugin _notifPlugin =
      FlutterLocalNotificationsPlugin();

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    // Initialise Supabase inside this isolate (each isolate needs its own init)
    try {
      await Supabase.initialize(
        url: AppConfig.supabaseUrl,
        anonKey: AppConfig.supabaseAnonKey,
      );
    } catch (_) {
      // Already initialised; this can happen if the service is restarted
    }
    _supabase = Supabase.instance.client;

    // Initialise local notifications (needed in this isolate too)
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _notifPlugin
        .initialize(const InitializationSettings(android: android));

    final prefs = await SharedPreferences.getInstance();
    final sessionId = prefs.getString(_kActiveSession);
    if (sessionId == null) {
      // Nothing to track
      await FlutterForegroundTask.stopService();
      return;
    }

    // Begin continuous GPS stream — updates Supabase on every 5m movement
    _positionSub = Geolocator.getPositionStream(
      locationSettings: buildLocationSettings(background: true),
    ).listen((pos) async {
      try {
        await _supabase!.from('location_sessions').update({
          'latitude': pos.latitude,
          'longitude': pos.longitude,
          'updated_at': DateTime.now().toIso8601String(),
        }).eq('id', sessionId);

        // Keep notification text fresh so Android won't think the service stalled
        await FlutterForegroundTask.updateService(
          notificationTitle: "📍 FollowMe",
          notificationText: 'Sharing your location in real time...',
        );

        // ── Proximity check (background-safe) ────────────────────────────────
        if (!_proximityAlertSent) {
          await _checkProximity(pos, sessionId);
        }
      } catch (_) {}
    }, onError: (_) {});
  }

  // ── PROXIMITY CHECK ────────────────────────────────────────────────────────

  Future<void> _checkProximity(Position driverPos, String sessionId) async {
    try {
      final data = await _supabase!
          .from('location_sessions')
          .select('client_latitude, client_longitude')
          .eq('id', sessionId)
          .single();

      final clientLat = (data['client_latitude'] as num?)?.toDouble();
      final clientLng = (data['client_longitude'] as num?)?.toDouble();
      if (clientLat == null || clientLng == null) return;

      final dist = Geolocator.distanceBetween(
        driverPos.latitude,
        driverPos.longitude,
        clientLat,
        clientLng,
      );

      if (dist <= _proximityThresholdM) {
        _proximityAlertSent = true;
        await _fireArrivalNotification(dist);
      }
    } catch (_) {}
  }

  Future<void> _fireArrivalNotification(double dist) async {
    const android = AndroidNotificationDetails(
      'proximity_alerts',
      'Proximity Alerts',
      channelDescription: 'Alerts when you are near your passenger',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
    );
    await _notifPlugin.show(
      2, // id 2 — distinct from foreground (0) and UI-layer (1) notifications
      '\u00a1Has llegado! 🚕',
      'Estás a ${dist.round()} m del pasajero. Podés dejar de compartir tu ubicación.',
      const NotificationDetails(
        android: android,
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
    );
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    // GPS stream handles all updates — nothing needed here
  }

  @override
  Future<void> onDestroy(DateTime timestamp) async {
    await _positionSub?.cancel();
    _positionSub = null;

    // If prefs still contain the session ID the app was KILLED (not stopped
    // intentionally). Mark the session as inactive so the client page stops.
    final prefs = await SharedPreferences.getInstance();
    final sessionId = prefs.getString(_kActiveSession);
    if (sessionId != null && _supabase != null) {
      try {
        await _supabase!.from('location_sessions').update({
          'active': false,
          'updated_at': DateTime.now().toIso8601String(),
        }).eq('id', sessionId);
      } catch (_) {}
      await prefs.remove(_kActiveSession);
      await prefs.remove(_kActiveSessionLink);
    }
  }
}
