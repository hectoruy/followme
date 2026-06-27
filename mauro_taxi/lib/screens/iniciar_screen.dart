import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../main.dart';
import '../services/live_video_service.dart';
import '../services/location_task_handler.dart';
import '../config/platform_location.dart';
import 'detener_screen.dart';
import 'settings_screen.dart';

class IniciarScreen extends StatefulWidget {
  const IniciarScreen({super.key});

  @override
  State<IniciarScreen> createState() => _IniciarScreenState();
}

class _IniciarScreenState extends State<IniciarScreen>
    with TickerProviderStateMixin {
  final MapController _mapController = MapController();
  LatLng _currentPosition = const LatLng(-34.9011, -56.1645);
  bool _locationReady = false;
  bool _gpsEnabled = false;
  bool _isSharing = false;

  // Shows a splash while we check Supabase for an active session on startup
  bool _checkingSession = true;

  // GPS stream — only for LOCAL MAP display.
  // Supabase updates are handled entirely by the background foreground service.
  StreamSubscription<Position>? _mapPositionStream;

  late AnimationController _pingController;
  late AnimationController _buttonController;
  late Animation<double> _pingAnimation;
  late Animation<double> _buttonScale;

  // Driver profile (loaded from SharedPreferences)
  String _driverName = '';
  String _driverPhone = '';

  // State
  bool _proximityAlertSent = false;
  bool _followDriver = false;
  bool _liveVideoEnabled = false;

  // SharedPreferences keys — must match location_task_handler.dart
  static const _kActiveSession = 'active_session_id';
  static const _kActiveSessionLink = 'active_session_link';
  static const _kActiveSessionDriverSecret = 'active_session_driver_secret';

  final LiveVideoService _liveVideoService = LiveVideoService();

  // ── LIFECYCLE ─────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _pingController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
    _pingAnimation = Tween<double>(begin: 0.5, end: 1.5).animate(
      CurvedAnimation(parent: _pingController, curve: Curves.easeOut),
    );
    _buttonController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
    _buttonScale = Tween<double>(begin: 1.0, end: 0.95).animate(
      CurvedAnimation(parent: _buttonController, curve: Curves.easeInOut),
    );
    _loadSettings();
    _initLocation();
    _requestNotificationPermission();
    _checkForActiveSession();
  }

  @override
  void dispose() {
    _pingController.dispose();
    _buttonController.dispose();
    _mapPositionStream?.cancel();
    _liveVideoService.stop();
    // NOTE: we do NOT stop the foreground service or mark session inactive here.
    // The foreground service handles GPS→Supabase independently.
    // Session lifecycle is: Start → service running → (user presses Stop OR app killed).
    super.dispose();
  }

  // ── SESSION PERSISTENCE ───────────────────────────────────────────────────

  /// On startup: restore session if the app was reopened after being minimised.
  /// If the app was KILLED, the foreground service's onDestroy already cleared
  /// the prefs and marked active=false, so we'll find nothing here.
  Future<void> _checkForActiveSession() async {
    final prefs = await SharedPreferences.getInstance();
    final savedId = prefs.getString(_kActiveSession);
    final savedLink = prefs.getString(_kActiveSessionLink) ?? '';
    final savedDriverSecret = prefs.getString(_kActiveSessionDriverSecret);

    if (savedId == null) {
      if (mounted) setState(() => _checkingSession = false);
      return;
    }

    // Verify the session is still active in Supabase
    try {
      final data = await Supabase.instance.client
          .from('location_sessions')
          .select('id, active, driver_name, driver_phone, video_enabled')
          .eq('id', savedId)
          .single();

      if (data['active'] != true) {
        // Cleaned up by the background service (app kill scenario)
        await prefs.remove(_kActiveSession);
        await prefs.remove(_kActiveSessionLink);
        await prefs.remove(_kActiveSessionDriverSecret);
        if (mounted) setState(() => _checkingSession = false);
        return;
      }

      // Session is still live — restore UI state
      if (mounted) {
        setState(() {
          _isSharing = true;
          _checkingSession = false;
          _driverName = data['driver_name'] ?? _driverName;
          _driverPhone = data['driver_phone'] ?? _driverPhone;
          _liveVideoEnabled = data['video_enabled'] == true;
        });
      }

      // Restart the map GPS stream (background service already resumed for Supabase)
      _startMapPositionStream(savedId);
      if (data['video_enabled'] == true &&
          savedDriverSecret != null &&
          savedDriverSecret.isNotEmpty) {
        final liveVideoStarted =
            await _startLiveVideo(savedId, savedDriverSecret);
        if (!liveVideoStarted) {
          await Supabase.instance.client.from('location_sessions').update({
            'video_enabled': false,
            'updated_at': DateTime.now().toIso8601String(),
          }).eq('id', savedId);
          if (mounted) setState(() => _liveVideoEnabled = false);
        }
      }

      // Navigate straight to DetenerScreen
      if (mounted) {
        final link =
            savedLink.isNotEmpty ? savedLink : '$clientBaseUrl?id=$savedId';
        Navigator.of(context).push(
          PageRouteBuilder(
            pageBuilder: (_, animation, __) => DetenerScreen(
              sessionId: savedId,
              driverName: _driverName,
              shareLink: link,
              liveVideoEnabled: _liveVideoEnabled,
              liveVideoPreview: _liveVideoService.previewState,
              onLiveVideoChanged: (enabled) =>
                  _setLiveVideoEnabled(savedId, enabled),
              onSwitchCamera: _switchLiveCamera,
              onDetener: _detenerCompartir,
            ),
            transitionsBuilder: (_, animation, __, child) =>
                FadeTransition(opacity: animation, child: child),
            transitionDuration: const Duration(milliseconds: 400),
          ),
        );
      }
    } catch (_) {
      // Session not found — clean up
      await prefs.remove(_kActiveSession);
      await prefs.remove(_kActiveSessionLink);
      await prefs.remove(_kActiveSessionDriverSecret);
      if (mounted) setState(() => _checkingSession = false);
    }
  }

  Future<void> _saveActiveSession(
    String sessionId,
    String link, {
    String? driverSecret,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kActiveSession, sessionId);
    await prefs.setString(_kActiveSessionLink, link);
    if (driverSecret == null || driverSecret.isEmpty) {
      await prefs.remove(_kActiveSessionDriverSecret);
    } else {
      await prefs.setString(_kActiveSessionDriverSecret, driverSecret);
    }
  }

  Future<String> _ensureActiveSessionDriverSecret() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_kActiveSessionDriverSecret);
    if (existing != null && existing.isNotEmpty) return existing;

    final generated = '${const Uuid().v4()}${const Uuid().v4()}';
    await prefs.setString(_kActiveSessionDriverSecret, generated);
    return generated;
  }

  Future<void> _clearActiveSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kActiveSession);
    await prefs.remove(_kActiveSessionLink);
    await prefs.remove(_kActiveSessionDriverSecret);
  }

  // ── FOREGROUND SERVICE ────────────────────────────────────────────────────

  Future<void> _startForegroundService() async {
    await FlutterForegroundTask.startService(
      notificationTitle: "📍 FollowMe",
      notificationText: 'Sharing your location in real time...',
      callback: locationTaskCallback,
    );
  }

  Future<void> _stopForegroundService() async {
    await FlutterForegroundTask.stopService();
  }

  // ── GPS STREAM (map display only) ─────────────────────────────────────────

  /// Starts a GPS stream used ONLY to update the map marker.
  /// Supabase updates are done exclusively by the foreground service.
  void _startMapPositionStream(String sessionId) {
    _mapPositionStream?.cancel();
    _mapPositionStream = Geolocator.getPositionStream(
      locationSettings: buildLocationSettings(background: false),
    ).listen((pos) async {
      if (mounted) {
        setState(() {
          _currentPosition = LatLng(pos.latitude, pos.longitude);
          if (_followDriver) {
            _mapController.move(_currentPosition, _mapController.camera.zoom);
          }
        });
      }
      // Proximity check (5m notification) — runs only while app is in foreground
      if (!_proximityAlertSent) {
        await _checkPassengerProximity(pos, sessionId);
      }
    });
  }

  // ── PERMISSIONS & LOCATION INIT ───────────────────────────────────────────

  Future<void> _requestNotificationPermission() async {
    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: true, sound: true);
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _driverName = prefs.getString('driver_name') ?? '';
        _driverPhone = prefs.getString('driver_phone') ?? '';
      });
    }
  }

  Future<bool> _startLiveVideo(String sessionId, String driverSecret) async {
    final status = await Permission.camera.request();
    if (!status.isGranted) return false;

    try {
      await _liveVideoService.start(
        sessionId: sessionId,
        driverSecret: driverSecret,
      );
      return true;
    } catch (_) {
      await _liveVideoService.stop();
      return false;
    }
  }

  Future<void> _stopLiveVideo() async {
    await _liveVideoService.stop();
  }

  Future<bool> _setLiveVideoEnabled(String sessionId, bool enabled) async {
    if (enabled) {
      final status = await Permission.camera.request();
      if (!status.isGranted) return false;

      final driverSecret = await _ensureActiveSessionDriverSecret();
      try {
        await Supabase.instance.client.from('location_sessions').update({
          'video_enabled': true,
          'updated_at': DateTime.now().toIso8601String(),
        }).eq('id', sessionId);

        final started = await _startLiveVideo(sessionId, driverSecret);
        if (!started) {
          await Supabase.instance.client.from('location_sessions').update({
            'video_enabled': false,
            'updated_at': DateTime.now().toIso8601String(),
          }).eq('id', sessionId);
          return false;
        }

        if (mounted) setState(() => _liveVideoEnabled = true);
        return true;
      } catch (_) {
        await _liveVideoService.stop();
        return false;
      }
    }

    try {
      await _stopLiveVideo();
      await Supabase.instance.client.from('location_sessions').update({
        'video_enabled': false,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', sessionId);
      if (mounted) setState(() => _liveVideoEnabled = false);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _switchLiveCamera() async {
    try {
      await _liveVideoService.switchCamera();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _initLocation() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (mounted) setState(() => _gpsEnabled = serviceEnabled);

    final status = await Permission.location.request();
    if (!status.isGranted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text('Location permission is required to share your position'),
            backgroundColor: Color(0xFFBA1A1A),
          ),
        );
      }
      return;
    }

    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings:
            const LocationSettings(accuracy: LocationAccuracy.high),
      );
      if (mounted) {
        setState(() {
          _currentPosition = LatLng(position.latitude, position.longitude);
          _locationReady = true;
          _gpsEnabled = true;
        });
        _mapController.move(_currentPosition, 15.0);
      }
    } catch (_) {
      if (mounted) setState(() => _locationReady = true);
    }
  }

  // ── SETTINGS ──────────────────────────────────────────────────────────────

  Future<void> _openSettings() async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const SettingsScreen()),
    );
    if (result == true) await _loadSettings();
  }

  void _centerOnMyLocation() {
    setState(() => _followDriver = true);
    _mapController.move(_currentPosition, _mapController.camera.zoom);
  }

  // ── SHARE DIALOG ──────────────────────────────────────────────────────────

  Future<void> _showShareDialog(String link) async {
    try {
      await Share.share(
        link,
        subject: "Track my location — FollowMe",
      );
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: link));
      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Row(children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: const Color(0xFF003461),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.link, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Link Copied!',
                  style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 18,
                      color: Color(0xFF003461)),
                ),
              ),
            ]),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Your tracking link has been copied. Share it so passengers can follow you in real time.',
                  style: TextStyle(height: 1.5, color: Color(0xFF424750)),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0F4F8),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    link,
                    style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF003461),
                        fontWeight: FontWeight.w600),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Close',
                    style: TextStyle(color: Color(0xFF727781))),
              ),
              ElevatedButton.icon(
                icon: const Icon(Icons.copy, size: 16),
                label: const Text('Copy Again'),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: link));
                  Navigator.of(ctx).pop();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF003461),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ),
        );
      }
    }
  }

  // ── START SHARING ─────────────────────────────────────────────────────────

  Future<void> _iniciarCompartir() async {
    if (_isSharing) return;

    // 2. Check GPS service
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted) {
        await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Row(children: [
              Icon(Icons.gps_off, color: Color(0xFFBA1A1A)),
              SizedBox(width: 10),
              Text('GPS is Off',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
            ]),
            content: const Text(
              'GPS must be enabled so passengers can see exactly where you are.',
              style: TextStyle(height: 1.5),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Cancel',
                    style: TextStyle(color: Color(0xFF727781))),
              ),
              ElevatedButton.icon(
                icon: const Icon(Icons.settings, size: 18),
                label: const Text('Enable GPS'),
                onPressed: () {
                  Navigator.of(ctx).pop();
                  Geolocator.openLocationSettings();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF003461),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ),
        );
      }
      return;
    }

    await _buttonController.forward();
    await _buttonController.reverse();
    setState(() => _isSharing = true);

    final status = await Permission.location.request();
    if (!status.isGranted) {
      setState(() => _isSharing = false);
      return;
    }

    Position position;
    try {
      position = await Geolocator.getCurrentPosition(
          locationSettings:
              const LocationSettings(accuracy: LocationAccuracy.high));
    } catch (e) {
      setState(() => _isSharing = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error getting location: $e')));
      }
      return;
    }

    final sessionId = const Uuid().v4();
    _proximityAlertSent = false;
    _liveVideoEnabled = false;

    try {
      await Supabase.instance.client.from('location_sessions').insert({
        'id': sessionId,
        'latitude': position.latitude,
        'longitude': position.longitude,
        'active': true,
        'driver_name': _driverName,
        'driver_phone': _driverPhone,
        'video_enabled': false,
      });
    } catch (e) {
      setState(() => _isSharing = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Connection error: $e'),
            backgroundColor: const Color(0xFFBA1A1A),
          ),
        );
      }
      return;
    }

    final link = '$clientBaseUrl?id=$sessionId';
    // Persist to SharedPreferences (foreground service reads this)
    await _saveActiveSession(sessionId, link);

    // Start background foreground service (GPS → Supabase, survives background)
    await _startForegroundService();

    // Start map-only GPS stream (UI display)
    _startMapPositionStream(sessionId);

    // Show native share sheet
    await _showShareDialog(link);

    if (mounted) {
      Navigator.of(context).push(
        PageRouteBuilder(
          pageBuilder: (_, animation, __) => DetenerScreen(
            sessionId: sessionId,
            driverName: _driverName,
            shareLink: link,
            liveVideoEnabled: false,
            liveVideoPreview: _liveVideoService.previewState,
            onLiveVideoChanged: (enabled) =>
                _setLiveVideoEnabled(sessionId, enabled),
            onSwitchCamera: _switchLiveCamera,
            onDetener: _detenerCompartir,
          ),
          transitionsBuilder: (_, animation, __, child) =>
              FadeTransition(opacity: animation, child: child),
          transitionDuration: const Duration(milliseconds: 400),
        ),
      );
    }
  }

  // ── PROXIMITY ─────────────────────────────────────────────────────────────

  Future<void> _checkPassengerProximity(
      Position driverPos, String sessionId) async {
    try {
      final data = await Supabase.instance.client
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

      if (dist <= 50.0) {
        _proximityAlertSent = true;
        await _showArrivalNotification();
      }
    } catch (_) {}
  }

  Future<void> _showArrivalNotification() async {
    const AndroidNotificationDetails android = AndroidNotificationDetails(
      'proximity_alerts',
      'Proximity Alerts',
      channelDescription: 'Alerts when you are near your passenger',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
    );
    await flutterLocalNotificationsPlugin.show(
      1,
      "You've arrived! 🚕",
      "You are right next to your passenger. Open the app to stop sharing.",
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

  // ── STOP SHARING ──────────────────────────────────────────────────────────

  /// Called when user presses the red Stop button in DetenerScreen.
  ///
  /// Order matters:
  /// 1. Clear SharedPreferences FIRST → so background service's onDestroy
  ///    finds no sessionId and does nothing (we handled Supabase already).
  /// 2. Stop foreground service → onDestroy runs → is a no-op.
  /// 3. Cancel map GPS stream.
  void _detenerCompartir() {
    _clearActiveSession(); // fire-and-forget (fast write)
    _stopForegroundService(); // fire-and-forget
    _stopLiveVideo(); // fire-and-forget
    _mapPositionStream?.cancel();
    _mapPositionStream = null;
    _proximityAlertSent = false;
    setState(() {
      _isSharing = false;
      _followDriver = false;
    });
  }

  // ── BUILD ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final displayName =
        _driverName.isNotEmpty ? _driverName.toUpperCase() : 'DRIVER';

    // Splash screen while verifying active session
    if (_checkingSession) {
      return Scaffold(
        backgroundColor: const Color(0xFF003461),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('🚕', style: TextStyle(fontSize: 52)),
              const SizedBox(height: 24),
              const SizedBox(
                width: 36,
                height: 36,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 3,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                "FollowMe",
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.9),
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Checking active sessions...',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.55),
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      body: Stack(
        children: [
          // ── MAP ────────────────────────────────────────────────────────
          GestureDetector(
            onPanDown: (_) {
              if (mounted) setState(() => _followDriver = false);
            },
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: _currentPosition,
                initialZoom: 15.0,
                interactionOptions:
                    const InteractionOptions(flags: InteractiveFlag.all),
                onPositionChanged: (pos, hasGesture) {
                  if (hasGesture && mounted) {
                    setState(() => _followDriver = false);
                  }
                },
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.hectoruy.followme',
                ),
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _currentPosition,
                      width: 140,
                      height: 88,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 60,
                            height: 60,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                AnimatedBuilder(
                                  animation: _pingAnimation,
                                  builder: (_, __) => Transform.scale(
                                    scale: _pingAnimation.value,
                                    child: Container(
                                      width: 48,
                                      height: 48,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: const Color(0xFF003461)
                                            .withValues(
                                                alpha: 0.2 *
                                                    (1.5 -
                                                        _pingAnimation.value)),
                                      ),
                                    ),
                                  ),
                                ),
                                Container(
                                  width: 24,
                                  height: 24,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: const Color(0xFF003461),
                                    border: Border.all(
                                        color: Colors.white, width: 3),
                                    boxShadow: [
                                      BoxShadow(
                                        color: const Color(0xFF003461)
                                            .withValues(alpha: 0.4),
                                        blurRadius: 8,
                                        spreadRadius: 2,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.95),
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.1),
                                  blurRadius: 4,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Text(
                              displayName,
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF003461),
                                letterSpacing: 1.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // ── HEADER ─────────────────────────────────────────────────────
          Positioned(
            top: MediaQuery.of(context).padding.top + 16,
            left: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: const Color(0xFF003461),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.local_taxi,
                        color: Colors.white, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "FollowMe",
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                            color: Color(0xFF003461),
                          ),
                        ),
                        Text(
                          _driverName.isNotEmpty
                              ? 'Hi, $_driverName 👋'
                              : 'Tap ⚙️ to set your name',
                          style: const TextStyle(
                              fontSize: 11, color: Color(0xFF727781)),
                        ),
                      ],
                    ),
                  ),
                  if (_gpsEnabled && _locationReady)
                    _badge('GPS', const Color(0xFF059669))
                  else
                    _badge('GPS OFF', const Color(0xFFBA1A1A)),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: _openSettings,
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF0F4F8),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.settings,
                          color: Color(0xFF003461), size: 20),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── MY LOCATION FAB ────────────────────────────────────────────
          // Centered vertically on the right edge (like map zoom controls)
          Positioned(
            right: 16,
            top: 0,
            bottom: 0,
            child: Align(
              alignment: const Alignment(1.0, -0.65),
              child: AnimatedOpacity(
                opacity: _locationReady ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 300),
                child: GestureDetector(
                  onTap: _centerOnMyLocation,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: _followDriver
                          ? const Color(0xFF003461)
                          : Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color:
                              const Color(0xFF003461).withValues(alpha: 0.25),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                      border: Border.all(
                        color: const Color(0xFF003461).withValues(alpha: 0.15),
                        width: 1.5,
                      ),
                    ),
                    child: Icon(
                      Icons.my_location_rounded,
                      color: _followDriver
                          ? Colors.white
                          : const Color(0xFF003461),
                      size: 22,
                    ),
                  ),
                ),
              ),
            ),
          ),

          // ── SHARE BUTTON ───────────────────────────────────────────────
          Positioned(
            bottom: 60,
            left: 24,
            right: 24,
            child: ScaleTransition(
              scale: _buttonScale,
              child: GestureDetector(
                onTap: _isSharing ? null : _iniciarCompartir,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  height: 72,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: _isSharing
                          ? [const Color(0xFF9CA3AF), const Color(0xFF6B7280)]
                          : [
                              const Color(0xFF059669),
                              const Color(0xFF047857),
                            ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(36),
                    border: Border.all(color: Colors.white, width: 2.5),
                    boxShadow: _isSharing
                        ? []
                        : [
                            BoxShadow(
                              color: const Color(0xFF059669)
                                  .withValues(alpha: 0.45),
                              blurRadius: 24,
                              spreadRadius: 2,
                              offset: const Offset(0, 8),
                            ),
                          ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        _isSharing ? Icons.hourglass_top : Icons.share,
                        color: Colors.white,
                        size: 26,
                      ),
                      const SizedBox(width: 14),
                      Text(
                        _isSharing ? 'Starting...' : 'Share My Location',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _badge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color),
          ),
          const SizedBox(width: 5),
          Text(label,
              style: TextStyle(
                  fontSize: 10, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }
}
