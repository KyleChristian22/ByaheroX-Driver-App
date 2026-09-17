import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../icons/jeep_icon.dart';
import '../../../services/firestore_service.dart';
import '../../viewmodels/auth_viewmodel.dart';
import '../../viewmodels/jeepney_viewmodel.dart';
import '../../viewmodels/language_viewmodel.dart';
import '../../viewmodels/trip_viewmodel.dart';
import '../../widgets/driver_app_background.dart';

Color _getErrorColor(AuthErrorType type) {
  switch (type) {
    case AuthErrorType.networkError:
      return AppTheme.warning;
    case AuthErrorType.tooManyRequests:
      return Colors.deepOrange;
    case AuthErrorType.emailNotVerified:
      return AppTheme.warning;
    case AuthErrorType.userDisabled:
      return Colors.purple;
    default:
      return AppTheme.primaryRed;
  }
}

/// Login Screen for Driver App
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  String? _emailError;
  String? _passwordError;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _validateEmailField(String? value) {
    final languageViewModel = context.read<LanguageViewModel>();
    final isTagalog = languageViewModel.isTagalog;
    setState(() {
      if (value == null || value.isEmpty) {
        _emailError = isTagalog ? 'Kailangan ang email' : 'Email is required';
      } else if (!value.contains('@')) {
        _emailError = isTagalog
            ? 'Mangyaring maglagay ng wastong email address'
            : 'Please enter a valid email address';
      } else {
        _emailError = null;
      }
    });
  }

  void _validatePasswordField(String? value) {
    final languageViewModel = context.read<LanguageViewModel>();
    final isTagalog = languageViewModel.isTagalog;
    setState(() {
      if (value == null || value.isEmpty) {
        _passwordError =
            isTagalog ? 'Kailangan ang password' : 'Password is required';
      } else if (value != value.trim()) {
        _passwordError = isTagalog
            ? 'Ang password ay hindi maaaring magsimula o magtapos sa mga puwang'
            : 'Password cannot start or end with spaces';
      } else if (value.length < 8) {
        _passwordError = isTagalog
            ? 'Ang password ay dapat may hindi bababa sa 8 na character'
            : 'Password must be at least 8 characters';
      } else if (!RegExp(r'[a-zA-Z]').hasMatch(value) ||
          !RegExp(r'[0-9]').hasMatch(value)) {
        _passwordError = isTagalog
            ? 'Ang password ay dapat may parehong mga titik at numero'
            : 'Password must contain both letters and numbers';
      } else {
        _passwordError = null;
      }
    });
  }

  void _showForgotPasswordDialog() {
    final resetEmailController = TextEditingController();
    bool isResetLoading = false;
    final languageViewModel = context.read<LanguageViewModel>();
    final isTagalog = languageViewModel.isTagalog;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(isTagalog ? 'I-reset ang Password' : 'Reset Password'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                isTagalog
                    ? 'Ilagay ang iyong email address at padadalhan ka namin ng link para i-reset ang iyong password.'
                    : 'Enter your email address and we will send you a link to reset your password.',
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: resetEmailController,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  labelText: isTagalog ? 'Email' : 'Email',
                  hintText:
                      isTagalog ? 'Ilagay ang iyong email' : 'Enter your email',
                  prefixIcon: const Icon(Icons.email_outlined),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: isResetLoading ? null : () => Navigator.pop(context),
              child: Text(isTagalog ? 'Kanselahin' : 'Cancel'),
            ),
            ElevatedButton(
              onPressed: isResetLoading
                  ? null
                  : () async {
                      if (resetEmailController.text.trim().isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(isTagalog
                                ? 'Mangyaring ilagay ang iyong email'
                                : 'Please enter your email'),
                            backgroundColor: AppTheme.primaryRed,
                          ),
                        );
                        return;
                      }

                      final navigator = Navigator.of(context);
                      final scaffoldMessenger = ScaffoldMessenger.of(context);
                      setDialogState(() => isResetLoading = true);

                      final authViewModel = context.read<AuthViewModel>();
                      final success =
                          await authViewModel.sendPasswordResetEmail(
                        resetEmailController.text.trim(),
                      );

                      if (!mounted) return;
                      setDialogState(() => isResetLoading = false);

                      if (success) {
                        navigator.pop();
                        scaffoldMessenger.showSnackBar(
                          SnackBar(
                            content: Text(isTagalog
                                ? 'Naipadala ang password reset link! Suriin ang iyong email.'
                                : 'Password reset link sent! Check your email.'),
                            backgroundColor: AppTheme.success,
                          ),
                        );
                      } else {
                        scaffoldMessenger.showSnackBar(
                          SnackBar(
                            content: Text(authViewModel.error ??
                                (isTagalog
                                    ? 'Nabigong magpadala ng reset email'
                                    : 'Failed to send reset email')),
                            backgroundColor: AppTheme.primaryRed,
                          ),
                        );
                      }
                    },
              child: isResetLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      isTagalog ? 'Ipadala ang Reset Link' : 'Send Reset Link',
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleLogin() async {
    final authViewModel = context.read<AuthViewModel>();
    if (authViewModel.isLoading || authViewModel.isLockedOut) return;
    if (!_formKey.currentState!.validate()) return;

    FirestoreService.clearDriverCache();
    context.read<JeepneyViewModel>().resetState();
    context.read<TripViewModel>().reset();

    final result = await authViewModel.login(
      _emailController.text,
      _passwordController.text,
    );

    if (result.success && mounted) {
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
    } else if (result.errorType == AuthErrorType.emailNotVerified && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.error ?? 'Please verify your email.'),
          backgroundColor: AppTheme.warning,
          behavior: SnackBarBehavior.floating,
        ),
      );
      AppRouter.goToEmailVerification(context);
    } else if (!result.success && mounted && result.error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.error!),
          backgroundColor: _getErrorColor(result.errorType),
        ),
      );
    }
  }

  void _showLanguageSwitcher() {
    final languageViewModel = context.read<LanguageViewModel>();

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(18),
              child: Text(
                languageViewModel.isTagalog
                    ? 'Pumili ng Wika'
                    : 'Select Language',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.language_rounded),
              title: const Text('English'),
              trailing: languageViewModel.isEnglish
                  ? const Icon(Icons.check, color: AppTheme.primaryBlue)
                  : null,
              onTap: () {
                languageViewModel.setEnglish();
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.translate_rounded),
              title: const Text('Tagalog'),
              trailing: languageViewModel.isTagalog
                  ? const Icon(Icons.check, color: AppTheme.primaryBlue)
                  : null,
              onTap: () {
                languageViewModel.setTagalog();
                Navigator.pop(context);
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final languageViewModel = context.watch<LanguageViewModel>();
    final isTagalog = languageViewModel.isTagalog;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: DriverAppBackground(
        safeArea: false,
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            20,
            MediaQuery.paddingOf(context).top + 18,
            20,
            28,
          ),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment: Alignment.topRight,
                  child: OutlinedButton.icon(
                    onPressed: _showLanguageSwitcher,
                    icon: const Icon(Icons.language_rounded, size: 20),
                    label: Text(languageViewModel.isEnglish ? 'EN' : 'TL'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(92, 48),
                        backgroundColor: Colors.white,
                      side: const BorderSide(color: AppTheme.border),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                    ),
                  ),
                ),
                const SizedBox(height: 28),
                DriverGlassSurface(
                  padding: const EdgeInsets.all(22),
                  borderRadius: BorderRadius.circular(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Container(
                          width: 88,
                          height: 88,
                          decoration: BoxDecoration(
                            color: AppTheme.blueSurface,
                            borderRadius: BorderRadius.circular(22),
                            border: Border.all(
                              color:
                                  AppTheme.primaryBlue.withValues(alpha: 0.12),
                            ),
                          ),
                          child: const Center(
                            child: JeepIcon(
                              color: AppTheme.primaryBlue,
                              size: 54,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 22),
                      const Text(
                        'ByaheroX Driver',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w900,
                          color: AppTheme.textPrimary,
                          letterSpacing: 0,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        isTagalog
                            ? 'Ligtas at malinaw na biyahe, bawat pasada.'
                            : 'A safer, clearer way to manage every trip.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 16,
                          height: 1.35,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 26),
                      TextFormField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        autocorrect: false,
                        decoration: InputDecoration(
                          labelText: isTagalog ? 'Email' : 'Email',
                          hintText: isTagalog
                              ? 'Ilagay ang iyong email'
                              : 'Enter your email',
                          prefixIcon: const Icon(Icons.email_outlined),
                          errorText: _emailError,
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return isTagalog
                                ? 'Mangyaring ilagay ang iyong email'
                                : 'Please enter your email';
                          }
                          if (!value.contains('@')) {
                            return isTagalog
                                ? 'Mangyaring maglagay ng wastong email'
                                : 'Please enter a valid email';
                          }
                          return null;
                        },
                        onChanged: _validateEmailField,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) => _handleLogin(),
                        decoration: InputDecoration(
                          labelText: isTagalog ? 'Password' : 'Password',
                          hintText: isTagalog
                              ? 'Ilagay ang iyong password'
                              : 'Enter your password',
                          prefixIcon: const Icon(Icons.lock_outlined),
                          errorText: _passwordError,
                          suffixIcon: IconButton(
                            tooltip: _obscurePassword
                                ? (isTagalog
                                    ? 'Ipakita ang password'
                                    : 'Show password')
                                : (isTagalog
                                    ? 'Itago ang password'
                                    : 'Hide password'),
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                            ),
                            onPressed: () {
                              setState(() {
                                _obscurePassword = !_obscurePassword;
                              });
                            },
                          ),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return isTagalog
                                ? 'Mangyaring ilagay ang iyong password'
                                : 'Please enter your password';
                          }
                          if (value != value.trim()) {
                            return isTagalog
                                ? 'Ang password ay hindi maaaring magsimula o magtapos sa mga puwang'
                                : 'Password cannot start or end with spaces';
                          }
                          if (value.length < 8) {
                            return isTagalog
                                ? 'Ang password ay dapat may hindi bababa sa 8 na character'
                                : 'Password must be at least 8 characters';
                          }
                          if (!RegExp(r'[a-zA-Z]').hasMatch(value) ||
                              !RegExp(r'[0-9]').hasMatch(value)) {
                            return isTagalog
                                ? 'Ang password ay dapat may parehong mga titik at numero'
                                : 'Password must contain both letters and numbers';
                          }
                          return null;
                        },
                        onChanged: _validatePasswordField,
                      ),
                      const SizedBox(height: 10),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: _showForgotPasswordDialog,
                          child: Text(
                            isTagalog
                                ? 'Nakalimutan ang Password?'
                                : 'Forgot Password?',
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Consumer<AuthViewModel>(
                        builder: (context, authViewModel, _) {
                          return ElevatedButton.icon(
                            onPressed: authViewModel.isLoading ||
                                    authViewModel.isLockedOut
                                ? null
                                : _handleLogin,
                            icon: authViewModel.isLoading
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.login_rounded),
                            label: Text(
                              authViewModel.isLockedOut
                                  ? (isTagalog
                                      ? 'Subukan muli sa ${authViewModel.lockoutRemainingTime}'
                                      : 'Try again in ${authViewModel.lockoutRemainingTime}')
                                  : (isTagalog ? 'Mag-login' : 'Login'),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                DriverGlassSurface(
                  padding: const EdgeInsets.all(16),
                  backgroundColor: AppTheme.primaryBlue.withValues(alpha: 0.72),
                  borderColor: AppTheme.accentBlue.withValues(alpha: 0.42),
                  child: Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.shield_outlined,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          isTagalog
                              ? 'Panatilihing aktibo ang account at sundin ang trip schedule.'
                              : 'Keep your account active and follow your assigned trip schedule.',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            height: 1.3,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
