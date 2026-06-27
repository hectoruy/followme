import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'config/app_config.dart';
import 'screens/iniciar_screen.dart';

const String supabaseUrl = AppConfig.supabaseUrl;
const String supabaseAnonKey = AppConfig.supabaseAnonKey;

// URL where the client HTML is hosted — update this after uploading to Netlify
const String clientBaseUrl = AppConfig.clientBaseUrl;

/// Global notifications plugin — used from IniciarScreen
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  AppConfig.validate();

  // ── Supabase ───────────────────────────────────────────────────────────────
  await Supabase.initialize(
    url: supabaseUrl,
    anonKey: supabaseAnonKey,
  );

  // ── Local Notifications ───────────────────────────────────────────────────
  const AndroidInitializationSettings androidInit =
      AndroidInitializationSettings('@mipmap/ic_launcher');
  // Permissions are requested explicitly later (see IniciarScreen), so don't
  // prompt during initialization on iOS.
  const DarwinInitializationSettings iosInit = DarwinInitializationSettings(
    requestAlertPermission: false,
    requestBadgePermission: false,
    requestSoundPermission: false,
  );
  await flutterLocalNotificationsPlugin.initialize(
    const InitializationSettings(android: androidInit, iOS: iosInit),
  );

  // ── Foreground Task (background GPS service) ──────────────────────────────
  // Must be called before using FlutterForegroundTask anywhere in the app.
  FlutterForegroundTask.initCommunicationPort();
  FlutterForegroundTask.init(
    androidNotificationOptions: AndroidNotificationOptions(
      channelId: 'wmd_location_channel',
      channelName: 'Location Sharing',
      channelDescription:
          'Keeps your location active while sharing with passengers.',
      channelImportance: NotificationChannelImportance.LOW,
      priority: NotificationPriority.LOW,
    ),
    iosNotificationOptions: const IOSNotificationOptions(
      showNotification: false,
      playSound: false,
    ),
    foregroundTaskOptions: ForegroundTaskOptions(
      eventAction: ForegroundTaskEventAction.repeat(60000), // 1-min keepalive
      autoRunOnBoot: false, // don't restart after reboot
      autoRunOnMyPackageReplaced: false,
      allowWakeLock: true, // keep CPU awake for GPS
      allowWifiLock: true, // keep wifi alive for Supabase
    ),
  );

  runApp(const WheresMyDriverApp());
}

class WheresMyDriverApp extends StatelessWidget {
  const WheresMyDriverApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "Where Is My Driver",
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF003461),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        fontFamily: 'Inter',
      ),
      home: const IniciarScreen(),
    );
  }
}
