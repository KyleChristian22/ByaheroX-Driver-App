import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'firebase_options.dart';

import 'core/theme/app_theme.dart';
import 'core/router/app_router.dart';
import 'presentation/viewmodels/auth_viewmodel.dart';
import 'presentation/viewmodels/jeepney_viewmodel.dart';
import 'presentation/viewmodels/trip_viewmodel.dart';
import 'presentation/viewmodels/language_viewmodel.dart';
import 'presentation/viewmodels/connectivity_viewmodel.dart';
import 'presentation/widgets/driver_app_background.dart';
import 'presentation/widgets/global_connectivity_banner.dart';
import 'services/analytics_tracking_service.dart';
import 'services/app_permission_service.dart';
import 'services/firestore_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Support both portrait and landscape driver layouts.
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  // Set system UI overlay style
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ),
  );

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => LanguageViewModel()),
        ChangeNotifierProvider(create: (_) => AuthViewModel()),
        ChangeNotifierProvider(create: (_) => JeepneyViewModel()),
        ChangeNotifierProvider(create: (_) => TripViewModel()),
        ChangeNotifierProvider(create: (_) => ConnectivityViewModel()),
      ],
      child: const ByaheroXDriverApp(),
    ),
  );

  // Run permission/plugin startup work after the first UI is visible. Browser
  // permission prompts can otherwise hold the app on a blank canvas.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(_initializeStartupServices());
  });
}

/// Flutter Local Notifications plugin
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

/// Initialize local notifications
Future<void> _initializeLocalNotifications() async {
  const AndroidInitializationSettings initializationSettingsAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher');

  const InitializationSettings initializationSettings = InitializationSettings(
    android: initializationSettingsAndroid,
  );

  await flutterLocalNotificationsPlugin.initialize(initializationSettings);
}

Future<void> _initializeStartupServices() async {
  try {
    await _initializeLocalNotifications();
  } catch (e) {
    debugPrint('Local notifications initialization failed: $e');
  }

  await _initializeFirebaseMessaging();

  try {
    await AppPermissionService.requestStartupPermissions();
  } catch (e) {
    debugPrint('Startup permission request failed: $e');
  }
}

/// Initialize Firebase Messaging and request permissions
Future<void> _initializeFirebaseMessaging() async {
  try {
    final FirebaseMessaging messaging = FirebaseMessaging.instance;

    if (kIsWeb) {
      debugPrint(
        'Firebase Messaging web permission request skipped until user action.',
      );
      return;
    }

    // Request notification permissions (iOS and Android 13+)
    final settings = await messaging.requestPermission(
      alert: true,
      announcement: false,
      badge: true,
      carPlay: false,
      criticalAlert: false,
      provisional: false,
      sound: true,
    );

    // Log the permission status
    debugPrint(
        'Notification permission status: ${settings.authorizationStatus}');

    // Get the FCM token
    try {
      final token = await messaging.getToken();
      debugPrint('FCM Token: $token');
    } catch (e) {
      debugPrint('Failed to get FCM token: $e');
    }

    // Handle foreground messages
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      debugPrint('Received foreground message: ${message.notification?.title}');
      _showLocalNotification(message);
    });

    // Handle when app is opened from notification
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      debugPrint(
          'App opened from notification: ${message.notification?.title}');
      if (AppRouter.navigatorKey.currentContext != null) {
        AppRouter.goToNotifications(AppRouter.navigatorKey.currentContext!);
      }
    });

    // Check if app was opened from a notification (cold start)
    final initialMessage = await messaging.getInitialMessage();
    if (initialMessage != null) {
      debugPrint(
          'App opened from cold start notification: ${initialMessage.notification?.title}');
      Future.delayed(const Duration(milliseconds: 500), () {
        if (AppRouter.navigatorKey.currentContext != null) {
          AppRouter.goToNotifications(AppRouter.navigatorKey.currentContext!);
        }
      });
    }
  } catch (e) {
    debugPrint('Firebase Messaging initialization failed: $e');
  }
}

/// Show local notification when FCM message is received in foreground
Future<void> _showLocalNotification(RemoteMessage message) async {
  const AndroidNotificationDetails androidPlatformChannelSpecifics =
      AndroidNotificationDetails(
    'commuter_notifications', // channel id
    'Commuter Notifications', // channel name
    channelDescription: 'Notifications about waiting commuters',
    importance: Importance.max,
    priority: Priority.high,
    showWhen: false,
  );

  const NotificationDetails platformChannelSpecifics =
      NotificationDetails(android: androidPlatformChannelSpecifics);

  await flutterLocalNotificationsPlugin.show(
    0, // notification id
    message.notification?.title ?? 'Notification',
    message.notification?.body ?? '',
    platformChannelSpecifics,
  );
}

/// Main application widget
class ByaheroXDriverApp extends StatefulWidget {
  const ByaheroXDriverApp({super.key});

  @override
  State<ByaheroXDriverApp> createState() => _ByaheroXDriverAppState();
}

class _ByaheroXDriverAppState extends State<ByaheroXDriverApp>
    with WidgetsBindingObserver {
  StreamSubscription<User?>? _authSubscription;
  Timer? _sessionHeartbeatTimer;
  Locale _locale = const Locale('en', 'US');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _authSubscription = FirebaseAuth.instance.authStateChanges().listen((
      user,
    ) {
      if (user == null) {
        _stopSessionHeartbeat();
        _clearDriverRuntimeState();
        return;
      }

      _resumeDriverSession();
    });

    if (FirebaseAuth.instance.currentUser != null) {
      _resumeDriverSession();
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<LanguageViewModel>().addListener(_onLanguageChanged);
    });
  }

  void _onLanguageChanged() {
    final newLocale = context.read<LanguageViewModel>().currentLocale;
    if (newLocale != _locale) {
      setState(() {
        _locale = newLocale;
      });
    }
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    _sessionHeartbeatTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    try {
      context.read<LanguageViewModel>().removeListener(_onLanguageChanged);
    } catch (_) {}
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    // When app is closed or terminated
    if (state == AppLifecycleState.detached ||
        state == AppLifecycleState.paused) {
      _pauseDriverSession();
      _cleanupOnAppClose();
    } else if (state == AppLifecycleState.resumed) {
      _resumeDriverSession();
    }
  }

  Future<void> _cleanupOnAppClose() async {
    final jeepneyId = TripViewModel.lastJeepneyId;
    if (jeepneyId != null && TripViewModel.isTripActiveStatic) {
      try {
        // Use setJeepneyOfflineStatus to preserve trip data when app is backgrounded/closed
        // This only updates isOnline to false and timestamp, keeping routeId, originTerminal, destinationTerminal, crowdStatus intact
        await FirestoreService.setJeepneyOfflineStatus(jeepneyId,
            keepTripData: true);
        debugPrint(
            'Cleanup: App closed but trip still active - location preserved');
      } catch (e) {
        debugPrint('Error during app cleanup: $e');
      }
    }
  }

  void _resumeDriverSession() {
    unawaited(AnalyticsTrackingService.startOrResumeDriverSession());
    _sessionHeartbeatTimer?.cancel();
    _sessionHeartbeatTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      unawaited(AnalyticsTrackingService.heartbeatDriverSession());
    });
  }

  void _pauseDriverSession() {
    _stopSessionHeartbeat();
    unawaited(AnalyticsTrackingService.stopDriverSession());
  }

  void _stopSessionHeartbeat() {
    _sessionHeartbeatTimer?.cancel();
    _sessionHeartbeatTimer = null;
  }

  void _clearDriverRuntimeState() {
    FirestoreService.clearDriverCache();
    try {
      context.read<JeepneyViewModel>().resetState();
      context.read<TripViewModel>().reset();
    } catch (error) {
      debugPrint('Driver runtime state reset skipped: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ByaheroX Driver',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      navigatorKey: AppRouter.navigatorKey,
      initialRoute: AppRouter.authGate,
      onGenerateRoute: AppRouter.generateRoute,
      builder: (context, child) {
        return GlobalConnectivityBanner(
          child: DriverAppBackground(
            safeArea: false,
            child: child ?? const SizedBox.shrink(),
          ),
        );
      },
      locale: _locale,
      supportedLocales: LanguageViewModel.supportedLocales,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
    );
  }
}
