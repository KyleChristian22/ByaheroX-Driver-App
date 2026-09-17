import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'core/services/app_permission_service.dart';
import 'core/theme/app_theme.dart';
import 'core/router/app_router.dart';
import 'l10n/app_localizations.dart';
import 'presentation/viewmodels/auth_viewmodel.dart';
import 'presentation/viewmodels/jeepney_viewmodel.dart';
import 'presentation/viewmodels/jeep_info_provider.dart';
import 'presentation/viewmodels/pickup_location_provider.dart';
import 'presentation/viewmodels/connectivity_viewmodel.dart';
import 'presentation/viewmodels/language_viewmodel.dart';
import 'presentation/widgets/app_lifecycle_observer.dart';
import 'presentation/widgets/common/app_background.dart';
import 'presentation/widgets/global_connectivity_banner.dart';
import 'presentation/widgets/global_onboarding_banner.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _ignoreDisposedEngineFlutterViewHotRestartNoise();

  // Initialize Firebase
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Request app permissions needed by commuter features.
  await AppPermissionService.requestStartupPermissions();

  // Set preferred orientations
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Set system UI overlay style
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarContrastEnforced: false,
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );

  runApp(const ByaheroXApp());
}

void _ignoreDisposedEngineFlutterViewHotRestartNoise() {
  final defaultOnError = FlutterError.onError;

  FlutterError.onError = (FlutterErrorDetails details) {
    final isDisposedEngineViewError = details.exceptionAsString().contains(
      'Trying to render a disposed EngineFlutterView',
    );

    if (kDebugMode && kIsWeb && isDisposedEngineViewError) {
      return;
    }

    defaultOnError?.call(details);
  };
}

/// Main application widget
class ByaheroXApp extends StatelessWidget {
  const ByaheroXApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        // Language ViewModel - for app localization
        ChangeNotifierProvider(create: (_) => LanguageViewModel()),
        // Auth ViewModel
        ChangeNotifierProvider(create: (_) => AuthViewModel()),
        // Jeepney ViewModel
        ChangeNotifierProvider(create: (_) => JeepneyViewModel()),
        // Jeep Info Provider for bottom info strip
        ChangeNotifierProvider(create: (_) => JeepInfoProvider()),
        // Pickup Location Provider for commuter pickup feature
        ChangeNotifierProvider(create: (_) => PickupLocationProvider()),
        // Global internet connectivity status for offline alert
        ChangeNotifierProvider(create: (_) => ConnectivityViewModel()),
      ],
      child: AppLifecycleObserver(
        child: Consumer<LanguageViewModel>(
          builder: (context, languageViewModel, child) {
            return MaterialApp.router(
              title: 'ByaheroX',
              debugShowCheckedModeBanner: false,
              theme: AppTheme.lightTheme,
              scrollBehavior: const _NoGlowScrollBehavior(),
              routerConfig: AppRouter.router,
              builder: (context, child) {
                return GlobalConnectivityBanner(
                  child: GlobalOnboardingBanner(
                    child: AppBackground(
                      child: child ?? const SizedBox.shrink(),
                    ),
                  ),
                );
              },
              // Localization configuration
              localizationsDelegates: const [
                AppLocalizations.delegate,
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              supportedLocales: LanguageViewModel.supportedLocales,
              locale: languageViewModel.currentLocale,
              localeResolutionCallback: (locale, supportedLocales) {
                if (locale == null) return const Locale('en');
                for (final supportedLocale in supportedLocales) {
                  if (supportedLocale.languageCode == locale.languageCode) {
                    return supportedLocale;
                  }
                }
                return const Locale('en');
              },
            );
          },
        ),
      ),
    );
  }
}

class _NoGlowScrollBehavior extends MaterialScrollBehavior {
  const _NoGlowScrollBehavior();

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    return child;
  }
}
