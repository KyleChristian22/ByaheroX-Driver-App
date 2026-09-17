import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/router/app_router.dart';
import '../../../l10n/app_localizations.dart';
import '../../viewmodels/auth_viewmodel.dart';

/// Login screen for ByaheroX app.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _emailFocusNode = FocusNode();
  final _passwordFocusNode = FocusNode();
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _emailFocusNode.dispose();
    _passwordFocusNode.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;

    final authViewModel = context.read<AuthViewModel>();
    final success = await authViewModel.login(
      _emailController.text.trim(),
      _passwordController.text,
    );

    if (success && mounted) {
      context.go(
        authViewModel.requiresPasswordChange
            ? AppRouter.changePassword
            : AppRouter.dashboard,
      );
      return;
    }

    if (!mounted) return;

    if (authViewModel.requiresEmailVerification) {
      _showToast(
        AppLocalizations.of(context).verificationEmailSent,
        Icons.mark_email_read_outlined,
      );
      context.go(AppRouter.verifyEmail);
      return;
    }

    if (authViewModel.requiresPasswordReset) {
      _showToast(
        authViewModel.error ?? AppLocalizations.of(context).forgotPasswordTitle,
        Icons.error_outline,
        isError: true,
      );
      context.go(AppRouter.forgotPassword);
      return;
    }

    if (authViewModel.error != null) {
      _showToast(authViewModel.error!, Icons.error_outline, isError: true);
      authViewModel.clearError();
    }
  }

  void _showToast(String message, IconData icon, {bool isError = false}) {
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          duration: const Duration(milliseconds: 2400),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(20, 0, 20, 22),
          elevation: 0,
          backgroundColor: Colors.transparent,
          content: _NeonToast(
            message: message,
            icon: icon,
            color: isError ? AppColors.accentRed : AppColors.neonBlue,
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) context.go(AppRouter.welcome);
        },
        child: Stack(
          children: [
            const Positioned.fill(child: SizedBox.shrink()),
            SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final isCompact = constraints.maxHeight < 900;
                  final horizontalPadding =
                      constraints.maxWidth < 390 ? 16.0 : 20.0;
                  final topPadding = isCompact ? 0.0 : 4.0;
                  final bottomPadding = isCompact ? 14.0 : 22.0;

                  return SingleChildScrollView(
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: EdgeInsets.fromLTRB(
                      horizontalPadding,
                      topPadding,
                      horizontalPadding,
                      bottomPadding,
                    ),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: 520,
                          minHeight: constraints.maxHeight - bottomPadding,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Tooltip(
                                message: 'Back to welcome',
                                child: IconButton(
                                  icon: const Icon(Icons.arrow_back),
                                  color: AppColors.textPrimary,
                                  iconSize: 30,
                                  onPressed: () =>
                                      context.go(AppRouter.welcome),
                                ),
                              ),
                            ),
                            SizedBox(height: isCompact ? 0 : AppDimensions.xs),
                            _LogoOrb(compact: isCompact),
                            SizedBox(
                              height: isCompact
                                  ? AppDimensions.xs
                                  : AppDimensions.sm,
                            ),
                            _NeonHeader(
                              title: l10n.loginTitle,
                              subtitle: l10n.loginSubtitle,
                              compact: isCompact,
                            ),
                            SizedBox(
                              height: isCompact
                                  ? AppDimensions.sm
                                  : AppDimensions.md,
                            ),
                            _NeonPanel(
                              compact: isCompact,
                              child: Form(
                                key: _formKey,
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    _NeonTextField(
                                      label: l10n.email,
                                      hint: l10n.emailHint,
                                      controller: _emailController,
                                      focusNode: _emailFocusNode,
                                      keyboardType:
                                          TextInputType.emailAddress,
                                      textInputAction: TextInputAction.next,
                                      prefixIcon: Icons.email_outlined,
                                      compact: isCompact,
                                      validator: (value) {
                                        if (value == null || value.isEmpty) {
                                          return l10n.errorLoginFailed;
                                        }
                                        if (!value.contains('@')) {
                                          return l10n.emailInvalid;
                                        }
                                        return null;
                                      },
                                      onFieldSubmitted: (_) {
                                        FocusScope.of(context).requestFocus(
                                          _passwordFocusNode,
                                        );
                                      },
                                    ),
                                    SizedBox(
                                      height: isCompact
                                          ? AppDimensions.sm
                                          : AppDimensions.lg,
                                    ),
                                    _NeonTextField(
                                      label: l10n.password,
                                      hint: l10n.passwordHint,
                                      controller: _passwordController,
                                      focusNode: _passwordFocusNode,
                                      obscureText: _obscurePassword,
                                      textInputAction: TextInputAction.done,
                                      prefixIcon: Icons.lock_outline,
                                      suffixIcon: _obscurePassword
                                          ? Icons.visibility_off_outlined
                                          : Icons.visibility_outlined,
                                      suffixTooltip: _obscurePassword
                                          ? 'Show password'
                                          : 'Hide password',
                                      compact: isCompact,
                                      onSuffixTap: () {
                                        setState(() {
                                          _obscurePassword = !_obscurePassword;
                                        });
                                      },
                                      validator: (value) {
                                        if (value == null || value.isEmpty) {
                                          return l10n.passwordRequired;
                                        }
                                        if (value.length < 6) {
                                          return l10n.passwordMinLength;
                                        }
                                        return null;
                                      },
                                      onFieldSubmitted: (_) => _handleLogin(),
                                    ),
                                    Align(
                                      alignment: Alignment.centerRight,
                                      child: TextButton(
                                        onPressed: () => context.go(
                                          AppRouter.forgotPassword,
                                        ),
                                        style: TextButton.styleFrom(
                                          foregroundColor: AppColors.primaryBlue,
                                          minimumSize: Size(
                                            48,
                                            isCompact ? 34 : 42,
                                          ),
                                          tapTargetSize:
                                              MaterialTapTargetSize.shrinkWrap,
                                          padding: EdgeInsets.symmetric(
                                            horizontal: AppDimensions.sm,
                                            vertical: isCompact
                                                ? AppDimensions.xs
                                                : AppDimensions.sm,
                                          ),
                                        ),
                                        child: Text(l10n.forgotPassword),
                                      ),
                                    ),
                                    SizedBox(
                                      height: isCompact
                                          ? AppDimensions.xs
                                          : AppDimensions.sm,
                                    ),
                                    Consumer<AuthViewModel>(
                                      builder: (context, auth, _) {
                                        return _NeonButton(
                                          text: l10n.login,
                                          icon: Icons.login,
                                          isLoading: auth.isLoading,
                                          compact: isCompact,
                                          onPressed: _handleLogin,
                                        );
                                      },
                                    ),
                                    SizedBox(
                                      height: isCompact
                                          ? AppDimensions.md
                                          : AppDimensions.lg,
                                    ),
                                    Consumer<AuthViewModel>(
                                      builder: (context, auth, _) {
                                        return _NeonButton(
                                          text: l10n.createAccount,
                                          icon: Icons.person_add_alt_1_outlined,
                                          isOutlined: true,
                                          isLoading: auth.isLoading,
                                          compact: isCompact,
                                          onPressed: () =>
                                              context.go(AppRouter.register),
                                        );
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LogoOrb extends StatelessWidget {
  const _LogoOrb({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final outerSize = compact ? 152.0 : 190.0;
    final innerSize = compact ? 112.0 : 144.0;
    final watermarkSize = compact ? 82.0 : 106.0;
    final logoSize = compact ? 76.0 : 96.0;

    return Center(
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: outerSize,
            height: outerSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: AppColors.surface.withValues(alpha: 0.34),
                width: 3,
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primaryBlue.withValues(alpha: 0.18),
                  blurRadius: 36,
                  spreadRadius: 3,
                ),
              ],
            ),
          ),
          Container(
            width: innerSize,
            height: innerSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.surface.withValues(alpha: 0.34),
              border: Border.all(
                color: AppColors.primaryBlueLight.withValues(alpha: 0.7),
              ),
            ),
          ),
          Opacity(
            opacity: 0.12,
            child: Image.asset(
              'assets/icons/commuter_icon.png',
              width: watermarkSize,
              height: watermarkSize,
              fit: BoxFit.contain,
            ),
          ),
          Semantics(
            image: true,
            label: 'ByaheroX commuter app logo',
            child: Container(
              width: logoSize,
              height: logoSize,
              padding: EdgeInsets.all(compact ? 6 : AppDimensions.sm),
              decoration: BoxDecoration(
                color: AppColors.surface.withValues(alpha: 0.4),
                borderRadius: AppDimensions.borderRadiusXl,
                border: Border.all(color: AppColors.neonBlue, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primaryBlue.withValues(alpha: 0.24),
                    blurRadius: 28,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: AppDimensions.borderRadiusLg,
                child: Image.asset(
                  'assets/icons/commuter_icon.png',
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NeonHeader extends StatelessWidget {
  const _NeonHeader({
    required this.title,
    required this.subtitle,
    required this.compact,
  });

  final String title;
  final String subtitle;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final titleStyle = compact
        ? Theme.of(context).textTheme.headlineSmall
        : Theme.of(context).textTheme.displaySmall;
    final subtitleStyle = compact
        ? Theme.of(context).textTheme.bodyMedium
        : Theme.of(context).textTheme.titleMedium;

    return Column(
      children: [
        Text(
          title,
          textAlign: TextAlign.center,
          style: titleStyle?.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w900,
                shadows: [
                  Shadow(
                    color: AppColors.neonBlue.withValues(alpha: 0.75),
                    blurRadius: 18,
                  ),
                ],
              ),
        ),
        const SizedBox(height: AppDimensions.xs),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: subtitleStyle?.copyWith(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w500,
              ),
        ),
      ],
    );
  }
}

class _NeonPanel extends StatelessWidget {
  const _NeonPanel({required this.child, required this.compact});

  final Widget child;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(compact ? 13 : AppDimensions.md),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.34),
        borderRadius: BorderRadius.circular(compact ? 22 : 26),
        border: Border.all(color: AppColors.neonBlue, width: 2),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryBlue.withValues(alpha: 0.2),
            blurRadius: 30,
            spreadRadius: 1,
          ),
          BoxShadow(
            color: AppColors.accentRed.withValues(alpha: 0.18),
            blurRadius: 24,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _NeonTextField extends StatelessWidget {
  const _NeonTextField({
    required this.label,
    required this.hint,
    required this.controller,
    required this.prefixIcon,
    this.focusNode,
    this.keyboardType,
    this.textInputAction,
    this.obscureText = false,
    this.suffixIcon,
    this.suffixTooltip,
    this.onSuffixTap,
    this.validator,
    this.onFieldSubmitted,
    required this.compact,
  });

  final String label;
  final String hint;
  final TextEditingController controller;
  final FocusNode? focusNode;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final bool obscureText;
  final IconData prefixIcon;
  final IconData? suffixIcon;
  final String? suffixTooltip;
  final VoidCallback? onSuffixTap;
  final String? Function(String?)? validator;
  final ValueChanged<String>? onFieldSubmitted;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide(
        color: AppColors.primaryBlueLight.withValues(alpha: 0.72),
        width: 1.5,
      ),
    );
    final focusedBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: AppColors.neonBlue, width: 2.5),
    );
    final errorBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: AppColors.accentRed, width: 2),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: (compact
                  ? Theme.of(context).textTheme.titleSmall
                  : Theme.of(context).textTheme.titleMedium)
              ?.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w800,
              ),
        ),
        SizedBox(height: compact ? 3 : AppDimensions.xs),
        TextFormField(
          controller: controller,
          focusNode: focusNode,
          keyboardType: keyboardType,
          textInputAction: textInputAction,
          obscureText: obscureText,
          validator: validator,
          onFieldSubmitted: onFieldSubmitted,
          style: (compact
                  ? Theme.of(context).textTheme.bodyLarge
                  : Theme.of(context).textTheme.titleMedium)
              ?.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
          cursorColor: AppColors.neonBlue,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(
              color: AppColors.textSecondary.withValues(alpha: 0.78),
              fontSize: compact ? 15 : 17,
            ),
            filled: true,
            fillColor: AppColors.surface.withValues(alpha: 0.3),
            contentPadding: EdgeInsets.symmetric(
              horizontal: compact ? AppDimensions.md : AppDimensions.lg,
              vertical: compact ? 10 : AppDimensions.md,
            ),
            prefixIcon: Icon(prefixIcon, color: AppColors.primaryBlue),
            suffixIcon: suffixIcon == null
                ? null
                : Tooltip(
                    message: suffixTooltip ?? 'Toggle password visibility',
                    child: IconButton(
                      onPressed: onSuffixTap,
                      icon: Icon(suffixIcon, color: AppColors.neonBlue),
                    ),
                  ),
            border: border,
            enabledBorder: border,
            focusedBorder: focusedBorder,
            errorBorder: errorBorder,
            focusedErrorBorder: errorBorder,
            errorMaxLines: 3,
            errorStyle: const TextStyle(
              color: AppColors.accentRed,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _NeonButton extends StatelessWidget {
  const _NeonButton({
    required this.text,
    required this.icon,
    required this.onPressed,
    this.isOutlined = false,
    this.isLoading = false,
    required this.compact,
  });

  final String text;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool isOutlined;
  final bool isLoading;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !isLoading;
    final child = isLoading
        ? const SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2.4,
              color: AppColors.textOnPrimary,
            ),
          )
        : Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: compact ? 22 : 28),
              SizedBox(width: compact ? AppDimensions.xs : AppDimensions.sm),
              Flexible(
                child: Text(
                  text,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          );

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        boxShadow: enabled
            ? [
                BoxShadow(
                  color: AppColors.primaryBlue.withValues(alpha: 0.24),
                  blurRadius: isOutlined ? 14 : 24,
                  spreadRadius: isOutlined ? 0 : 1,
                ),
              ]
            : const [],
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: compact ? 50 : 58),
        child: isOutlined
            ? OutlinedButton(
                onPressed: enabled ? onPressed : null,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primaryBlue,
                  disabledForegroundColor: AppColors.disabled,
                  side: BorderSide(
                    color: enabled
                        ? AppColors.electricBlue
                        : AppColors.border.withValues(alpha: 0.45),
                    width: 2,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                  textStyle: TextStyle(
                    fontSize: compact ? 15 : 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                child: child,
              )
            : ElevatedButton(
                onPressed: enabled ? onPressed : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.electricBlue,
                  foregroundColor: AppColors.textOnPrimary,
                  disabledBackgroundColor:
                      AppColors.electricBlue.withValues(alpha: 0.34),
                  disabledForegroundColor:
                      AppColors.textOnPrimary.withValues(alpha: 0.5),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                    side: const BorderSide(color: AppColors.neonBlue, width: 2),
                  ),
                  textStyle: TextStyle(
                    fontSize: compact ? 15 : 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                child: child,
              ),
      ),
    );
  }
}

class _NeonToast extends StatelessWidget {
  const _NeonToast({
    required this.message,
    required this.icon,
    required this.color,
  });

  final String message;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppDimensions.md,
          vertical: AppDimensions.sm,
        ),
        decoration: BoxDecoration(
          color: AppColors.midnightBlue.withValues(alpha: 0.94),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color, width: 1.5),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.55),
              blurRadius: 18,
            ),
          ],
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(width: AppDimensions.sm),
            Expanded(
              child: Text(
                message,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.textOnPrimary,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
