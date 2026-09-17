import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/router/app_router.dart';
import '../../viewmodels/auth_viewmodel.dart';
import '../../widgets/common/app_background.dart';
import '../../widgets/common/app_button.dart';

/// Screen shown after registration while Firebase email verification is pending.
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
        content: Row(
          children: [
            Icon(
              backgroundColor == AppColors.error
                  ? Icons.error_outline
                  : Icons.check_circle_outline,
              color: AppColors.textOnPrimary,
            ),
            const SizedBox(width: AppDimensions.sm),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: backgroundColor,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _handleCheckVerification() async {
    final authViewModel = context.read<AuthViewModel>();
    final verified = await authViewModel.checkEmailVerification();

    if (!mounted) {
      return;
    }
    if (verified) {
      _showSnackBar(AppStrings.emailVerifiedSuccess, AppColors.primary);
      if (!mounted) {
        return;
      }
      context.go(
        authViewModel.requiresPasswordChange
            ? AppRouter.changePassword
            : AppRouter.dashboard,
      );
      return;
    }

    _showSnackBar(
      authViewModel.error ?? AppStrings.emailNotVerified,
      AppColors.error,
    );
    authViewModel.clearError();
  }

  Future<void> _handleResendVerification() async {
    final authViewModel = context.read<AuthViewModel>();
    final sent = await authViewModel.resendEmailVerification();

    if (!mounted) {
      return;
    }
    _showSnackBar(
      sent
          ? AppStrings.verificationEmailSent
          : authViewModel.error ?? AppStrings.verificationCheckFailed,
      sent ? AppColors.success : AppColors.error,
    );
    authViewModel.clearError();
  }

  Future<void> _handleBackToLogin() async {
    await context.read<AuthViewModel>().logout();
    if (mounted) {
      context.go(AppRouter.login);
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    const cardMaxWidth = 480.0;
    final authViewModel = context.watch<AuthViewModel>();
    final email = authViewModel.verificationEmail;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _handleBackToLogin();
      },
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
            onPressed: _handleBackToLogin,
          ),
        ),
        extendBodyBehindAppBar: true,
        body: Container(
          color: Colors.transparent,
          child: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(
                  horizontal: screenWidth * 0.05,
                  vertical: screenHeight * 0.03,
                ),
                child: GlassSurface(
                  width: cardMaxWidth,
                  padding: EdgeInsets.all(screenWidth * 0.06),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          color: AppColors.primarySurface,
                          borderRadius: AppDimensions.borderRadiusLg,
                        ),
                        child: const Icon(
                          Icons.mark_email_read_outlined,
                          color: AppColors.primary,
                          size: 40,
                        ),
                      ),
                      const SizedBox(height: AppDimensions.lg),
                      Text(
                        AppStrings.verifyEmailTitle,
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.bold,
                            ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: AppDimensions.sm),
                      Text(
                        AppStrings.verifyEmailSubtitle,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      if (email.isNotEmpty) ...[
                        const SizedBox(height: AppDimensions.md),
                        Text(
                          email,
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(
                                color: AppColors.primary,
                                fontWeight: FontWeight.w700,
                              ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                      const SizedBox(height: AppDimensions.md),
                      Text(
                        AppStrings.verifyEmailInstructions,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: AppDimensions.xl),
                      AppButton(
                        text: AppStrings.checkVerification,
                        icon: Icons.verified_outlined,
                        isLoading: authViewModel.isLoading,
                        onPressed: _handleCheckVerification,
                      ),
                      const SizedBox(height: AppDimensions.sm),
                      AppButton(
                        text: AppStrings.resendVerificationEmail,
                        icon: Icons.refresh_outlined,
                        isOutlined: true,
                        isLoading: authViewModel.isLoading,
                        onPressed: _handleResendVerification,
                      ),
                      const SizedBox(height: AppDimensions.sm),
                      AppButtonSecondary(
                        text: AppStrings.backToLogin,
                        icon: Icons.login_outlined,
                        onPressed: _handleBackToLogin,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
