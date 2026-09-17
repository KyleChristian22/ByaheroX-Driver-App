import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/router/app_router.dart';
import '../../../services/firestore_service.dart';
import '../../viewmodels/auth_viewmodel.dart';
import '../../viewmodels/jeepney_viewmodel.dart';
import '../../viewmodels/trip_viewmodel.dart';
import '../../widgets/driver_app_background.dart';

class EmailVerificationScreen extends StatefulWidget {
  const EmailVerificationScreen({super.key});

  @override
  State<EmailVerificationScreen> createState() =>
      _EmailVerificationScreenState();
}

class _EmailVerificationScreenState extends State<EmailVerificationScreen> {
  void _showSnackBar(String message, Color backgroundColor) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: backgroundColor,
      ),
    );
  }

  Future<void> _handleCheckVerification() async {
    final authViewModel = context.read<AuthViewModel>();
    final result = await authViewModel.checkEmailVerification();

    if (!mounted) return;

    if (result.success) {
      _showSnackBar('Email verified successfully!', Colors.green);
      if (!mounted) return;

      if (authViewModel.requiresPasswordChange) {
        AppRouter.goToChangePassword(context);
      } else {
        FirestoreService.clearDriverCache();
        context.read<JeepneyViewModel>().resetState();
        context.read<TripViewModel>().reset();
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
      return;
    }

    _showSnackBar(
      result.error ?? 'Email is not verified yet.',
      Colors.red.shade700,
    );
    authViewModel.clearError();
  }

  Future<void> _handleResendVerification() async {
    final authViewModel = context.read<AuthViewModel>();
    final sent = await authViewModel.resendEmailVerification();

    if (!mounted) return;

    _showSnackBar(
      sent
          ? 'Verification email sent! Check your inbox.'
          : authViewModel.error ?? 'Failed to send verification email.',
      sent ? Colors.green : Colors.red.shade700,
    );
    authViewModel.clearError();
  }

  Future<void> _handleBackToLogin() async {
    await context.read<AuthViewModel>().logout();
    if (mounted) {
      AppRouter.goToLogin(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    const primaryBlue = AppTheme.primaryBlue;
    const darkBlue = AppTheme.darkBlue;
    final authViewModel = context.watch<AuthViewModel>();
    final email = authViewModel.verificationEmail;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: DriverAppBackground(
        safeArea: false,
        child: SafeArea(
          child: PopScope(
            canPop: false,
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 40),
                    Center(
                      child: Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          color: primaryBlue.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Icon(
                          Icons.mark_email_read_outlined,
                          color: primaryBlue,
                          size: 40,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Center(
                      child: Text(
                        'Verify your email',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: darkBlue,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Center(
                      child: Text(
                        'Please verify your email address to continue.',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    if (email.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Center(
                        child: Text(
                          email,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: primaryBlue,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    const Center(
                      child: Text(
                        'We sent a verification link to your email. Please check your inbox and click the link, then come back here.',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 32),
                    ElevatedButton(
                      onPressed: authViewModel.isLoading
                          ? null
                          : _handleCheckVerification,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: authViewModel.isLoading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text(
                              'I\'ve verified, check now',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: authViewModel.isLoading
                          ? null
                          : _handleResendVerification,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        side: const BorderSide(color: primaryBlue),
                      ),
                      child: const Text(
                        'Resend verification email',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: primaryBlue,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed:
                          authViewModel.isLoading ? null : _handleBackToLogin,
                      child: const Text(
                        'Back to Login',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ),
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
