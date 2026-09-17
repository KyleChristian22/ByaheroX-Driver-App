import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/router/app_router.dart';
import '../../../l10n/app_localizations.dart';
import '../../viewmodels/auth_viewmodel.dart';
import '../../viewmodels/language_viewmodel.dart';
import '../../widgets/common/app_background.dart';
import '../../widgets/common/app_button.dart';

/// Welcome screen for ByaheroX app.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final languageViewModel = context.watch<LanguageViewModel>();

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _showStayOnWelcomeToast(context);
      },
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: AppBackground(
          child: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isCompact = constraints.maxHeight < 720;
                final horizontalPadding = constraints.maxWidth < 390
                    ? AppDimensions.md
                    : AppDimensions.lg;
                final topInset =
                    isCompact ? AppDimensions.sm : AppDimensions.md;
                final bottomInset =
                    isCompact ? AppDimensions.md : AppDimensions.xl;
                final minHeight =
                    constraints.maxHeight - topInset - bottomInset;
                final topGap = (constraints.maxHeight * 0.035)
                    .clamp(AppDimensions.md, AppDimensions.xl)
                    .toDouble();
                final brandGap = (constraints.maxHeight * 0.04)
                    .clamp(AppDimensions.md, AppDimensions.xl)
                    .toDouble();
                final actionGap =
                    isCompact ? AppDimensions.sm : AppDimensions.md;

                return SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(
                    horizontalPadding,
                    topInset,
                    horizontalPadding,
                    bottomInset,
                  ),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: 520,
                        minHeight: minHeight > 0 ? minHeight : 0.0,
                      ),
                      child: IntrinsicHeight(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Align(
                              alignment: Alignment.topRight,
                              child: _buildLanguageSwitchButton(
                                context,
                                languageViewModel,
                              ),
                            ),
                            SizedBox(height: topGap),
                            const Spacer(),
                            _WelcomeBrandCard(
                              appName: l10n.appName,
                              subtitle: l10n.welcomeSubtitle,
                              compact: isCompact,
                            ),
                            SizedBox(height: brandGap),
                            _WelcomeActions(
                              loginLabel: l10n.login,
                              createLabel: l10n.createAccount,
                              guestLabel: l10n.continueAsGuest,
                              gap: actionGap,
                              onLogin: () => context.go(AppRouter.login),
                              onCreate: () => context.go(AppRouter.register),
                              onGuest: () async {
                                final authViewModel =
                                    context.read<AuthViewModel>();
                                final success =
                                    await authViewModel.loginAsGuest();
                                if (success && context.mounted) {
                                  context.go(AppRouter.home);
                                }
                              },
                            ),
                            const Spacer(flex: 2),
                          ],
                        ),
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

  void _showStayOnWelcomeToast(BuildContext context) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('Choose an option to continue.'),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 2),
        ),
      );
  }

  Widget _buildLanguageSwitchButton(
    BuildContext context,
    LanguageViewModel languageViewModel,
  ) {
    final label = languageViewModel.isEnglish ? 'English' : 'Filipino';

    return Tooltip(
      message: 'Change language',
      child: Semantics(
        button: true,
        label: 'Change language. Current language is $label',
        child: OutlinedButton.icon(
          onPressed: () => _showLanguageSelector(context, languageViewModel),
          icon: const Icon(Icons.language, size: 18),
          label: Text(languageViewModel.isEnglish ? 'EN' : 'FIL'),
          style: OutlinedButton.styleFrom(
            backgroundColor: AppColors.surface.withValues(alpha: 0.22),
            foregroundColor: AppColors.primaryBlue,
            minimumSize: const Size(0, 42),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            padding: const EdgeInsets.symmetric(
              horizontal: AppDimensions.md,
              vertical: AppDimensions.xs,
            ),
            side: BorderSide(
              color: AppColors.primaryBlue.withValues(alpha: 0.78),
              width: 1.4,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: AppDimensions.borderRadiusFull,
            ),
          ),
        ),
      ),
    );
  }

  void _showLanguageSelector(
    BuildContext context,
    LanguageViewModel languageViewModel,
  ) {
    final l10n = AppLocalizations.of(context);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      builder: (context) => SafeArea(
        child: Padding(
          padding: AppDimensions.paddingLg,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.language,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: AppDimensions.lg),
              _buildLanguageOption(
                context: context,
                languageCode: 'EN',
                languageName: l10n.languageEnglish,
                isSelected: languageViewModel.isEnglish,
                onTap: () {
                  languageViewModel.setEnglish();
                  Navigator.pop(context);
                },
              ),
              const SizedBox(height: AppDimensions.sm),
              _buildLanguageOption(
                context: context,
                languageCode: 'FIL',
                languageName: l10n.languageTagalog,
                isSelected: languageViewModel.isTagalog,
                onTap: () {
                  languageViewModel.setTagalog();
                  Navigator.pop(context);
                },
              ),
              const SizedBox(height: AppDimensions.md),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLanguageOption({
    required BuildContext context,
    required String languageCode,
    required String languageName,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Semantics(
      button: true,
      selected: isSelected,
      label: '$languageName language',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppDimensions.borderRadiusLg,
          child: Container(
            constraints: const BoxConstraints(
              minHeight: AppDimensions.buttonHeightMd,
            ),
            padding: AppDimensions.paddingMd,
            decoration: BoxDecoration(
              color: isSelected
                  ? AppColors.primaryBlueSurface.withValues(alpha: 0.75)
                  : AppColors.surface.withValues(alpha: 0.42),
              borderRadius: AppDimensions.borderRadiusLg,
              border: Border.all(
                color: isSelected ? AppColors.primaryBlue : AppColors.border,
                width: isSelected ? 2 : 1,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppColors.primaryBlue
                        : AppColors.primaryBlueSurface,
                    borderRadius: AppDimensions.borderRadiusMd,
                  ),
                  child: Text(
                    languageCode,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: isSelected
                              ? AppColors.textOnPrimary
                              : AppColors.primaryBlue,
                        ),
                  ),
                ),
                const SizedBox(width: AppDimensions.md),
                Expanded(
                  child: Text(
                    languageName,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (isSelected)
                  const Icon(
                    Icons.check_circle,
                    color: AppColors.primaryBlue,
                    semanticLabel: 'Selected',
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _WelcomeBrandCard extends StatelessWidget {
  const _WelcomeBrandCard({
    required this.appName,
    required this.subtitle,
    required this.compact,
  });

  final String appName;
  final String subtitle;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final logoFrameSize = compact ? 96.0 : 116.0;
    final logoSize = compact ? 68.0 : 82.0;

    return GlassSurface(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? AppDimensions.md : AppDimensions.lg,
        vertical: compact ? AppDimensions.lg : AppDimensions.xl,
      ),
      backgroundColor: AppColors.surface.withValues(alpha: 0.24),
      borderColor: AppColors.surface.withValues(alpha: 0.5),
      borderRadius: AppDimensions.borderRadiusXl,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            image: true,
            label: 'ByaheroX commuter app logo',
            child: Container(
              width: logoFrameSize,
              height: logoFrameSize,
              padding: EdgeInsets.all(compact ? AppDimensions.sm : 12),
              decoration: BoxDecoration(
                color: AppColors.surface.withValues(alpha: 0.34),
                borderRadius: AppDimensions.borderRadiusXl,
                border: Border.all(
                  color: AppColors.neonBlue.withValues(alpha: 0.72),
                  width: 1.6,
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primaryBlue.withValues(alpha: 0.18),
                    blurRadius: 28,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: Center(
                child: ClipRRect(
                  borderRadius: AppDimensions.borderRadiusLg,
                  child: Image.asset(
                    'assets/icons/commuter_icon.png',
                    width: logoSize,
                    height: logoSize,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ),
          ),
          SizedBox(height: compact ? AppDimensions.md : AppDimensions.lg),
          Text(
            appName,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: AppColors.primaryBlueDark,
                  fontWeight: FontWeight.w900,
                ),
          ),
          const SizedBox(height: AppDimensions.xs),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: AppColors.textSecondary,
                  height: 1.35,
                  fontWeight: FontWeight.w500,
                ),
          ),
        ],
      ),
    );
  }
}

class _WelcomeActions extends StatelessWidget {
  const _WelcomeActions({
    required this.loginLabel,
    required this.createLabel,
    required this.guestLabel,
    required this.gap,
    required this.onLogin,
    required this.onCreate,
    required this.onGuest,
  });

  final String loginLabel;
  final String createLabel;
  final String guestLabel;
  final double gap;
  final VoidCallback onLogin;
  final VoidCallback onCreate;
  final VoidCallback onGuest;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppButton(
          text: loginLabel,
          icon: Icons.login,
          onPressed: onLogin,
        ),
        SizedBox(height: gap),
        AppButton(
          text: createLabel,
          icon: Icons.person_add_outlined,
          isOutlined: true,
          onPressed: onCreate,
        ),
        SizedBox(height: gap),
        _GuestButton(
          label: guestLabel,
          onPressed: onGuest,
        ),
      ],
    );
  }
}

class _GuestButton extends StatelessWidget {
  const _GuestButton({
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.map_outlined, size: 22),
        label: Text(
          label,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
        ),
        style: OutlinedButton.styleFrom(
          backgroundColor: AppColors.surface.withValues(alpha: 0.22),
          foregroundColor: AppColors.primaryBlue,
          minimumSize: const Size.fromHeight(52),
          padding: const EdgeInsets.symmetric(
            horizontal: AppDimensions.lg,
            vertical: AppDimensions.sm,
          ),
          side: BorderSide(
            color: AppColors.surface.withValues(alpha: 0.45),
            width: 1.2,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: AppDimensions.borderRadiusFull,
          ),
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            letterSpacing: 0,
          ),
        ),
      ),
    );
  }
}
