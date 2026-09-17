import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../viewmodels/connectivity_viewmodel.dart';

class GlobalConnectivityBanner extends StatelessWidget {
  const GlobalConnectivityBanner({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        Consumer<ConnectivityViewModel>(
          builder: (context, connectivity, _) {
            return Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: _ConnectivityBannerOverlay(
                hasCheckedConnection: connectivity.hasCheckedConnection,
                isOffline: connectivity.isOffline,
              ),
            );
          },
        ),
      ],
    );
  }
}

class _ConnectivityBannerOverlay extends StatefulWidget {
  const _ConnectivityBannerOverlay({
    required this.hasCheckedConnection,
    required this.isOffline,
  });

  final bool hasCheckedConnection;
  final bool isOffline;

  @override
  State<_ConnectivityBannerOverlay> createState() =>
      _ConnectivityBannerOverlayState();
}

class _ConnectivityBannerOverlayState
    extends State<_ConnectivityBannerOverlay> {
  Timer? _hideRestoredTimer;
  bool _showRestored = false;

  @override
  void didUpdateWidget(covariant _ConnectivityBannerOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (!widget.hasCheckedConnection) return;

    if (widget.isOffline) {
      _hideRestoredTimer?.cancel();
      if (_showRestored) {
        setState(() => _showRestored = false);
      }
      return;
    }

    if (oldWidget.isOffline && !widget.isOffline) {
      _hideRestoredTimer?.cancel();
      setState(() => _showRestored = true);
      _hideRestoredTimer = Timer(const Duration(seconds: 3), () {
        if (!mounted) return;
        setState(() => _showRestored = false);
      });
    }
  }

  @override
  void dispose() {
    _hideRestoredTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final showOffline = widget.hasCheckedConnection && widget.isOffline;
    final showRestored = widget.hasCheckedConnection && _showRestored;
    final shouldShow = showOffline || showRestored;

    return IgnorePointer(
      ignoring: !shouldShow,
      child: AnimatedSlide(
        offset: shouldShow ? Offset.zero : const Offset(0, -1),
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
        child: AnimatedOpacity(
          opacity: shouldShow ? 1 : 0,
          duration: const Duration(milliseconds: 180),
          child: _ConnectionBanner(
            color: showOffline ? AppTheme.primaryRed : AppTheme.success,
            icon: showOffline ? Icons.wifi_off_rounded : Icons.wifi_rounded,
            message:
                showOffline ? 'No internet connection' : 'Connection restored',
          ),
        ),
      ),
    );
  }
}

class _ConnectionBanner extends StatelessWidget {
  const _ConnectionBanner({
    required this.color,
    required this.icon,
    required this.message,
  });

  final Color color;
  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.paddingOf(context).top;

    return Padding(
      padding: EdgeInsets.fromLTRB(12, topPadding + 8, 12, 0),
      child: Material(
        color: color,
        elevation: 10,
        shadowColor: color.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: SafeArea(
            top: false,
            bottom: false,
            child: Row(
              children: [
                Icon(
                  icon,
                  color: Colors.white,
                  size: 24,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    message,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                            ) ??
                        const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
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
