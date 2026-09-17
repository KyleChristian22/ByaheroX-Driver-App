import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_dimensions.dart';
import '../../core/services/app_sound_service.dart';
import '../viewmodels/pickup_location_provider.dart';

class GlobalOnboardingBanner extends StatelessWidget {
  const GlobalOnboardingBanner({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        Consumer<PickupLocationProvider>(
          builder: (context, pickupProvider, _) {
            return Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: _OnboardingBannerOverlay(
                hasPending: pickupProvider.pendingOnboardNotification,
                onConsume: pickupProvider.consumeOnboardNotification,
              ),
            );
          },
        ),
      ],
    );
  }
}

class _OnboardingBannerOverlay extends StatefulWidget {
  const _OnboardingBannerOverlay({
    required this.hasPending,
    required this.onConsume,
  });

  final bool hasPending;
  final VoidCallback onConsume;

  @override
  State<_OnboardingBannerOverlay> createState() =>
      _OnboardingBannerOverlayState();
}

class _OnboardingBannerOverlayState extends State<_OnboardingBannerOverlay> {
  static const Duration _autoDismissDuration = Duration(seconds: 4);
  static const Duration _animationDuration = Duration(milliseconds: 240);

  Timer? _hideTimer;
  bool _show = false;

  @override
  void didUpdateWidget(covariant _OnboardingBannerOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.hasPending && !_show) {
      widget.onConsume();
      unawaited(AppSoundService.playOnboardNotification());
      _hideTimer?.cancel();
      setState(() => _show = true);
      _hideTimer = Timer(_autoDismissDuration, _dismiss);
    }
  }

  void _dismiss() {
    if (!mounted) return;
    _hideTimer?.cancel();
    setState(() => _show = false);
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: !_show,
      child: AnimatedSlide(
        offset: _show ? Offset.zero : const Offset(0, -1),
        duration: _animationDuration,
        curve: Curves.easeOutCubic,
        child: AnimatedOpacity(
          opacity: _show ? 1 : 0,
          duration: const Duration(milliseconds: 180),
          child: _NotificationBanner(
            color: AppColors.success,
            icon: Icons.event_seat_outlined,
            title: 'You are on board',
            subtitle: 'The driver has confirmed your boarding.',
            semanticLabel: 'You are on board - driver confirmed',
          ),
        ),
      ),
    );
  }
}

class _NotificationBanner extends StatelessWidget {
  const _NotificationBanner({
    required this.color,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.semanticLabel,
  });

  final Color color;
  final IconData icon;
  final String title;
  final String subtitle;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.paddingOf(context).top;

    return Semantics(
      liveRegion: true,
      label: semanticLabel,
      child: Material(
        color: color,
        elevation: AppDimensions.elevationLg,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            AppDimensions.md,
            topPadding + AppDimensions.sm,
            AppDimensions.md,
            AppDimensions.md,
          ),
          child: SafeArea(
            top: false,
            bottom: false,
            child: Row(
              children: [
                Icon(icon, color: AppColors.textOnPrimary, size: 24),
                const SizedBox(width: AppDimensions.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context)
                            .textTheme
                            .titleSmall
                            ?.copyWith(
                              color: AppColors.textOnPrimary,
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      Text(
                        subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(
                              color: AppColors.textOnPrimary
                                  .withValues(alpha: 0.9),
                              fontWeight: FontWeight.w600,
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
