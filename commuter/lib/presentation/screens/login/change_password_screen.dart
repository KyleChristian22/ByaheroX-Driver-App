import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/router/app_router.dart';
import '../../viewmodels/auth_viewmodel.dart';
import '../../widgets/common/app_background.dart';
import '../../widgets/common/app_button.dart';
import '../../widgets/common/app_text_field.dart';

class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _passwordController = TextEditingController();
  final _repeatPasswordController = TextEditingController();
  bool _obscurePassword = true;
  bool _obscureRepeatPassword = true;

  @override
  void dispose() {
    _passwordController.dispose();
    _repeatPasswordController.dispose();
    super.dispose();
  }

  Future<void> _handleSubmit() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    final authViewModel = context.read<AuthViewModel>();
    final success = await authViewModel.completeRequiredPasswordChange(
      newPassword: _passwordController.text,
      repeatPassword: _repeatPasswordController.text,
    );

    if (!mounted) {
      return;
    }
    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              Icon(Icons.check_circle_outline, color: AppColors.textOnPrimary),
              SizedBox(width: 8),
              Expanded(child: Text(AppStrings.passwordUpdatedSuccess)),
            ],
          ),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
        ),
      );
      context.go(AppRouter.dashboard);
      return;
    }

    final error = authViewModel.error ?? AppStrings.errorGeneric;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: AppColors.textOnPrimary),
            const SizedBox(width: 8),
            Expanded(child: Text(error)),
          ],
        ),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
      ),
    );
    authViewModel.clearError();
  }

  Future<void> _useForgotPassword() async {
    await context.read<AuthViewModel>().logout();
    if (mounted) {
      context.go(AppRouter.forgotPassword);
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    const cardMaxWidth = 480.0;
    final authViewModel = context.watch<AuthViewModel>();

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      body: PopScope(
        canPop: false,
        child: Container(
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
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(
                            color: AppColors.primarySurface,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Icon(
                            Icons.lock_reset_outlined,
                            color: AppColors.primary,
                            size: 40,
                          ),
                        ),
                        const SizedBox(height: 24),
                        Text(
                          AppStrings.changePasswordTitle,
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(
                                color: AppColors.textPrimary,
                                fontWeight: FontWeight.bold,
                              ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          AppStrings.changePasswordSubtitle,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: AppColors.textSecondary),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 24),
                        AppTextField(
                          label: AppStrings.newPassword,
                          hint: AppStrings.passwordHint,
                          controller: _passwordController,
                          obscureText: _obscurePassword,
                          prefixIcon: Icons.lock_outlined,
                          suffixIcon: _obscurePassword
                              ? Icons.visibility_off
                              : Icons.visibility,
                          suffixTooltip: _obscurePassword
                              ? 'Show password'
                              : 'Hide password',
                          onSuffixIconTap: () {
                            setState(() {
                              _obscurePassword = !_obscurePassword;
                            });
                          },
                          validator: (value) =>
                              AuthValidator.validateRequiredNewPassword(
                                value,
                              ).errorMessage,
                        ),
                        const SizedBox(height: 16),
                        AppTextField(
                          label: AppStrings.repeatNewPassword,
                          hint: AppStrings.passwordHint,
                          controller: _repeatPasswordController,
                          obscureText: _obscureRepeatPassword,
                          textInputAction: TextInputAction.done,
                          prefixIcon: Icons.lock_reset_outlined,
                          suffixIcon: _obscureRepeatPassword
                              ? Icons.visibility_off
                              : Icons.visibility,
                          suffixTooltip: _obscureRepeatPassword
                              ? 'Show password'
                              : 'Hide password',
                          onSuffixIconTap: () {
                            setState(() {
                              _obscureRepeatPassword = !_obscureRepeatPassword;
                            });
                          },
                          onFieldSubmitted: (_) => _handleSubmit(),
                          validator: (value) =>
                              AuthValidator.validateConfirmPassword(
                                _passwordController.text,
                                value,
                              ).errorMessage,
                        ),
                        const SizedBox(height: 24),
                        AppButton(
                          text: AppStrings.updatePassword,
                          icon: Icons.check_circle_outline,
                          isLoading: authViewModel.isLoading,
                          onPressed: _handleSubmit,
                        ),
                        const SizedBox(height: 12),
                        AppButtonSecondary(
                          text: AppStrings.forgotPassword,
                          icon: Icons.lock_reset,
                          onPressed: authViewModel.isLoading
                              ? null
                              : _useForgotPassword,
                        ),
                      ],
                    ),
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
