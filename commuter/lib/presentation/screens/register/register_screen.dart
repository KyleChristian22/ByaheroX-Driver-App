import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/router/app_router.dart';
import '../../../l10n/app_localizations.dart';
import '../../viewmodels/auth_viewmodel.dart';
import '../../widgets/common/app_background.dart';
import '../../widgets/common/app_button.dart';
import '../../widgets/common/app_text_field.dart';

/// Register screen for creating a new account
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _middleNameController = TextEditingController();
  final _phoneNumberController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _repeatPasswordController = TextEditingController();
  final _firstNameFocusNode = FocusNode();
  final _lastNameFocusNode = FocusNode();
  final _middleNameFocusNode = FocusNode();
  final _phoneNumberFocusNode = FocusNode();
  final _emailFocusNode = FocusNode();
  final _passwordFocusNode = FocusNode();
  final _repeatPasswordFocusNode = FocusNode();
  bool _obscurePassword = true;
  bool _obscureRepeatPassword = true;

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _middleNameController.dispose();
    _phoneNumberController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _repeatPasswordController.dispose();
    _firstNameFocusNode.dispose();
    _lastNameFocusNode.dispose();
    _middleNameFocusNode.dispose();
    _phoneNumberFocusNode.dispose();
    _emailFocusNode.dispose();
    _passwordFocusNode.dispose();
    _repeatPasswordFocusNode.dispose();
    super.dispose();
  }

  Future<void> _handleRegister() async {
    if (_formKey.currentState!.validate()) {
      final authViewModel = context.read<AuthViewModel>();
      final success = await authViewModel.register(
        firstName: _firstNameController.text.trim(),
        lastName: _lastNameController.text.trim(),
        middleName: _middleNameController.text.trim(),
        phoneNumber: _phoneNumberController.text.trim(),
        email: _emailController.text.trim(),
        password: _passwordController.text,
        repeatPassword: _repeatPasswordController.text,
      );

      if (success && mounted) {
        final l10n = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(
                  Icons.check_circle_outline,
                  color: AppColors.textOnPrimary,
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(l10n.registrationSuccessful)),
              ],
            ),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
          ),
        );
        context.go(AppRouter.verifyEmail);
      } else if (mounted && authViewModel.error != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(
                  Icons.error_outline,
                  color: AppColors.textOnPrimary,
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(authViewModel.error!)),
              ],
            ),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
            action: SnackBarAction(
              label: 'OK',
              textColor: Colors.white,
              onPressed: () {
                ScaffoldMessenger.of(context).hideCurrentSnackBar();
              },
            ),
          ),
        );
        authViewModel.clearError();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // Get screen size using MediaQuery
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    // Calculate responsive values
    final paddingHorizontal = screenWidth * 0.05; // 5% of screen width
    const cardMaxWidth = 480.0;
    final logoSize = screenWidth * 0.15; // 15% of screen width, max ~80
    final iconSize = logoSize * 0.5;
    final titleFontSize = screenWidth * 0.07; // 7% of screen width
    final bodyFontSize = screenWidth * 0.04; // 4% of screen width
    final buttonHeight = screenHeight * 0.06; // 6% of screen height

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
          onPressed: () => context.go(AppRouter.login),
        ),
      ),
      extendBodyBehindAppBar: true,
      body: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) {
            context.go(AppRouter.login);
          }
        },
        child: Container(
          color: Colors.transparent,
          child: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  padding: EdgeInsets.symmetric(
                    horizontal: paddingHorizontal,
                    vertical: screenHeight * 0.02,
                  ),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight:
                          constraints.maxHeight -
                          MediaQuery.of(context).padding.top -
                          MediaQuery.of(context).padding.bottom,
                    ),
                    child: Form(
                      key: _formKey,
                      autovalidateMode: AutovalidateMode.onUserInteraction,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(height: screenHeight * 0.03),

                          // Logo
                          Center(
                            child: Container(
                              width: logoSize.clamp(60.0, 100.0),
                              height: logoSize.clamp(60.0, 100.0),
                              decoration: BoxDecoration(
                                color: AppColors.surface.withValues(alpha: 0.34),
                                borderRadius: BorderRadius.circular(
                                  logoSize.clamp(60.0, 100.0) * 0.2,
                                ),
                                border: Border.all(
                                  color: AppColors.surface.withValues(alpha: 0.48),
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: AppColors.primaryBlue.withValues(alpha: 0.18),
                                    blurRadius: 22,
                                    offset: const Offset(0, 10),
                                  ),
                                ],
                              ),
                              child: Icon(
                                Icons.person_add,
                                size: iconSize.clamp(30.0, 50.0),
                                color: AppColors.primary,
                              ),
                            ),
                          ),
                          SizedBox(height: screenHeight * 0.03),

                          // Title
                          Text(
                            l10n.registerTitle,
                            style: TextStyle(
                              fontSize: titleFontSize.clamp(24.0, 36.0),
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          SizedBox(height: screenHeight * 0.01),

                          // Subtitle
                          Text(
                            l10n.registerSubtitle,
                            style: TextStyle(
                              fontSize: bodyFontSize.clamp(14.0, 18.0),
                              color: AppColors.textSecondary,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          SizedBox(height: screenHeight * 0.03),

                          // Form Card
                          Center(
                            child: GlassSurface(
                              width: cardMaxWidth,
                              padding: EdgeInsets.all(screenWidth * 0.05),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  // First Name Field
                                  AppTextField(
                                    label: l10n.firstName,
                                    hint: l10n.firstNameHint,
                                    controller: _firstNameController,
                                    focusNode: _firstNameFocusNode,
                                    textInputAction: TextInputAction.next,
                                    prefixIcon: Icons.person_outlined,
                                    validator: (value) =>
                                        AuthValidator.validateFirstName(
                                          value,
                                        ).errorMessage,
                                    onFieldSubmitted: (_) {
                                      FocusScope.of(context).requestFocus(_lastNameFocusNode);
                                    },
                                  ),
                                  SizedBox(height: screenHeight * 0.018),

                                  // Last Name Field
                                  AppTextField(
                                    label: l10n.lastName,
                                    hint: l10n.lastNameHint,
                                    controller: _lastNameController,
                                    focusNode: _lastNameFocusNode,
                                    textInputAction: TextInputAction.next,
                                    prefixIcon: Icons.person_outlined,
                                    validator: (value) =>
                                        AuthValidator.validateLastName(
                                          value,
                                        ).errorMessage,
                                    onFieldSubmitted: (_) {
                                      FocusScope.of(context).requestFocus(_middleNameFocusNode);
                                    },
                                  ),
                                  SizedBox(height: screenHeight * 0.018),

                                  // Middle Name Field
                                  AppTextField(
                                    label: l10n.middleName,
                                    hint: l10n.middleNameHint,
                                    controller: _middleNameController,
                                    focusNode: _middleNameFocusNode,
                                    textInputAction: TextInputAction.next,
                                    prefixIcon: Icons.badge_outlined,
                                    validator: (value) =>
                                        AuthValidator.validateMiddleName(
                                          value,
                                        ).errorMessage,
                                    onFieldSubmitted: (_) {
                                      FocusScope.of(context).requestFocus(_phoneNumberFocusNode);
                                    },
                                  ),
                                  SizedBox(height: screenHeight * 0.018),

                                  // Phone Number Field
                                  AppTextField(
                                    label: l10n.phoneNumber,
                                    hint: l10n.phoneNumberHint,
                                    controller: _phoneNumberController,
                                    keyboardType: TextInputType.phone,
                                    prefixIcon: Icons.phone_outlined,
                                    inputFormatters: [
                                      FilteringTextInputFormatter.digitsOnly,
                                      LengthLimitingTextInputFormatter(11),
                                    ],
                                    validator: (value) =>
                                        AuthValidator.validatePhoneNumber(
                                          value,
                                        ).errorMessage,
                                    onFieldSubmitted: (_) {
                                      FocusScope.of(context).requestFocus(_emailFocusNode);
                                    },
                                  ),
                                  SizedBox(height: screenHeight * 0.018),

                                  // Email Field
                                  AppTextField(
                                    label: l10n.emailAddress,
                                    hint: l10n.emailHint,
                                    controller: _emailController,
                                    focusNode: _emailFocusNode,
                                    keyboardType: TextInputType.emailAddress,
                                    textInputAction: TextInputAction.next,
                                    prefixIcon: Icons.email_outlined,
                                    validator: (value) =>
                                        AuthValidator.validateEmail(
                                          value,
                                        ).errorMessage,
                                    onFieldSubmitted: (_) {
                                      FocusScope.of(context).requestFocus(_passwordFocusNode);
                                    },
                                  ),
                                  SizedBox(height: screenHeight * 0.018),

                                  // Password Field
                                  AppTextField(
                                    label: l10n.password,
                                    hint: l10n.passwordHint,
                                    controller: _passwordController,
                                    focusNode: _passwordFocusNode,
                                    obscureText: _obscurePassword,
                                    textInputAction: TextInputAction.next,
                                    prefixIcon: Icons.lock_outlined,
                                    suffixIcon: _obscurePassword
                                        ? Icons.visibility_off_outlined
                                        : Icons.visibility_outlined,
                                    suffixTooltip: _obscurePassword
                                        ? 'Show password'
                                        : 'Hide password',
                                    onSuffixIconTap: () {
                                      setState(() {
                                        _obscurePassword = !_obscurePassword;
                                      });
                                    },
                                    validator: (value) =>
                                        AuthValidator.validatePassword(
                                          value,
                                        ).errorMessage,
                                    onFieldSubmitted: (_) {
                                      FocusScope.of(context).requestFocus(_repeatPasswordFocusNode);
                                    },
                                  ),
                                  SizedBox(height: screenHeight * 0.018),

                                  // Confirm Password Field
                                  AppTextField(
                                    label: l10n.confirmPassword,
                                    hint: l10n.confirmPasswordHint,
                                    controller: _repeatPasswordController,
                                    focusNode: _repeatPasswordFocusNode,
                                    obscureText: _obscureRepeatPassword,
                                    textInputAction: TextInputAction.done,
                                    prefixIcon: Icons.lock_outlined,
                                    suffixIcon: _obscureRepeatPassword
                                        ? Icons.visibility_off_outlined
                                        : Icons.visibility_outlined,
                                    suffixTooltip: _obscureRepeatPassword
                                        ? 'Show password'
                                        : 'Hide password',
                                    onSuffixIconTap: () {
                                      setState(() {
                                        _obscureRepeatPassword =
                                            !_obscureRepeatPassword;
                                      });
                                    },
                                    validator: (value) =>
                                        AuthValidator.validateConfirmPassword(
                                          _passwordController.text,
                                          value,
                                        ).errorMessage,
                                    onFieldSubmitted: (_) => _handleRegister(),
                                  ),
                                  SizedBox(height: screenHeight * 0.025),

                                  // Register Button
                                  Consumer<AuthViewModel>(
                                    builder: (context, auth, _) {
                                      return SizedBox(
                                        height: buttonHeight.clamp(48.0, 60.0),
                                        child: AppButton(
                                          text: l10n.signUp,
                                          isLoading: auth.isLoading,
                                          onPressed: _handleRegister,
                                        ),
                                      );
                                    },
                                  ),
                                  SizedBox(height: screenHeight * 0.015),

                                  // Login Link
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        l10n.alreadyHaveAccount + ' ',
                                        style: TextStyle(
                                          color: AppColors.textSecondary,
                                          fontSize: bodyFontSize.clamp(
                                            12.0,
                                            16.0,
                                          ),
                                        ),
                                      ),
                                      GestureDetector(
                                        onTap: () =>
                                            context.go(AppRouter.login),
                                        child: Text(
                                          l10n.login,
                                          style: TextStyle(
                                            color: AppColors.primary,
                                            fontSize: bodyFontSize.clamp(
                                              12.0,
                                              16.0,
                                            ),
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                          SizedBox(height: screenHeight * 0.05),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
