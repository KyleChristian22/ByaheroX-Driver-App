import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../services/firestore_service.dart';
import '../../viewmodels/auth_viewmodel.dart';
import '../../viewmodels/jeepney_viewmodel.dart';
import '../../viewmodels/trip_viewmodel.dart';
import '../../widgets/driver_app_background.dart';

class StartupAuthGate extends StatefulWidget {
  const StartupAuthGate({super.key});

  @override
  State<StartupAuthGate> createState() => _StartupAuthGateState();
}

class _StartupAuthGateState extends State<StartupAuthGate> {
  bool _isChecking = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _restoreSession();
    });
  }

  Future<void> _restoreSession() async {
    setState(() {
      _isChecking = true;
      _error = null;
    });

    final authViewModel = context.read<AuthViewModel>();
    final result = await authViewModel.validateSavedSession();

    if (!mounted) return;

    if (!result.success) {
      if (result.errorType == AuthErrorType.emailNotVerified) {
        AppRouter.goToEmailVerification(context);
        return;
      }

      if (result.errorType == AuthErrorType.networkError ||
          authViewModel.currentUser != null) {
        setState(() {
          _isChecking = false;
          _error = result.error ??
              'Could not restore your session. Check your connection and try again.';
        });
        return;
      }

      AppRouter.goToLogin(context);
      return;
    }

    FirestoreService.clearDriverCache();
    context.read<JeepneyViewModel>().resetState();
    context.read<TripViewModel>().reset();

    if (authViewModel.requiresPasswordChange) {
      AppRouter.goToChangePassword(context);
      return;
    }

    final jeepneyViewModel = context.read<JeepneyViewModel>();
    await jeepneyViewModel.initializeAfterLogin();

    if (!mounted) return;

    if (jeepneyViewModel.hasAssignedJeepney) {
      context
          .read<TripViewModel>()
          .setCurrentJeepneyId(jeepneyViewModel.jeepneyId);
    }

    AppRouter.goToMain(context);
  }

  @override
  Widget build(BuildContext context) {
    const primaryBlue = AppTheme.primaryBlue;
    const darkBlue = AppTheme.darkBlue;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: DriverAppBackground(
        safeArea: false,
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          color: primaryBlue.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: _isChecking
                            ? const Padding(
                                padding: EdgeInsets.all(18),
                                child: CircularProgressIndicator(
                                  strokeWidth: 3,
                                  color: primaryBlue,
                                ),
                              )
                            : const Icon(
                                Icons.wifi_off_rounded,
                                color: primaryBlue,
                                size: 38,
                              ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      _isChecking
                          ? 'Opening driver account'
                          : 'Connection issue',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: darkBlue,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _isChecking
                          ? 'Please wait while we check your saved session.'
                          : _error ??
                              'Could not restore your session. Check your connection and try again.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.grey,
                      ),
                    ),
                    if (!_isChecking) ...[
                      const SizedBox(height: 24),
                      ElevatedButton(
                        onPressed: _restoreSession,
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        child: const Text(
                          'Try Again',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: () => AppRouter.goToLogin(context),
                        child: const Text('Go to Login'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
