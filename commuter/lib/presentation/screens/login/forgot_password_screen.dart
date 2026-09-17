import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/router/app_router.dart';
import '../../../l10n/app_localizations.dart';
import '../../viewmodels/auth_viewmodel.dart';
import '../../widgets/common/app_background.dart';
import '../../widgets/common/app_button.dart';
import '../../widgets/common/app_text_field.dart';

/// Forgot Password screen for ByaheroX app.
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  bool _isEmailSent = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _handleResetPassword() async {
    if (_formKey.currentState!.validate()) {
      final authViewModel = context.read<AuthViewModel>();
      final success = await authViewModel.sendPasswordResetEmail(
        _emailController.text.trim(),
      );

      if (success && mounted) {
        setState(() => _isEmailSent = true);
      } else if (mounted && authViewModel.error != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error_outline, color: AppColors.textOnPrimary),
                const SizedBox(width: AppDimensions.sm),
                Expanded(child: Text(authViewModel.error!)),
              ],
            ),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: AppColors.textPrimary,
        leading: Tooltip(
          message: 'Back to login',
          child: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.go(AppRouter.login),
          ),
        ),
      ),
      body: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) context.go(AppRouter.login);
        },
        child: _ResetPasswordShell(
          icon: _isEmailSent
              ? Icons.check_circle_outline
              : Icons.lock_reset_outlined,
          title: _isEmailSent
              ? l10n.verificationEmailSent
              : l10n.forgotPasswordTitle,
          subtitle: _isEmailSent
              ? l10n.resetPasswordSuccess
              : l10n.forgotPasswordSubtitle,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!_isEmailSent) ...[
                Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      AppTextField(
                        label: l10n.email,
                        hint: l10n.emailHint,
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        prefixIcon: Icons.email_outlined,
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return l10n.emailRequired;
                          }
                          if (!value.contains('@')) return l10n.emailInvalid;
                          return null;
                        },
                      ),
                      const SizedBox(height: AppDimensions.lg),
                      Consumer<AuthViewModel>(
                        builder: (context, auth, _) {
                          return AppButton(
                            text: l10n.sendResetLink,
                            icon: Icons.mark_email_read_outlined,
                            isLoading: auth.isLoading,
                            onPressed: _handleResetPassword,
                          );
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppDimensions.md),
              ],
              AppButton(
                text: l10n.backToLogin,
                icon: Icons.arrow_back,
                isOutlined: _isEmailSent,
                onPressed: () => context.go(AppRouter.login),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ResetPasswordShell extends StatelessWidget {
  const _ResetPasswordShell({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.transparent,
      child: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: AppDimensions.paddingLg,
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: 480,
                    minHeight: constraints.maxHeight - AppDimensions.xl,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        width: 80,
                        height: 80,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: AppColors.surface.withValues(alpha: 0.42),
                          borderRadius: AppDimensions.borderRadiusXl,
                          border: Border.all(
                            color: AppColors.surface.withValues(alpha: 0.48),
                          ),
                        ),
                        child: Icon(
                          icon,
                          size: 42,
                          color: AppColors.primaryBlue,
                        ),
                      ),
                      const SizedBox(height: AppDimensions.lg),
                      Text(
                        title,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineLarge
                            ?.copyWith(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      const SizedBox(height: AppDimensions.sm),
                      Text(
                        subtitle,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.w500,
                            ),
                      ),
                      const SizedBox(height: AppDimensions.xl),
                      GlassSurface(
                        padding: AppDimensions.paddingLg,
                        child: child,
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
