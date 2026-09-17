import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/router/app_router.dart';
import '../../widgets/common/app_background.dart';

/// Splash screen for ByaheroX app
/// Displays app branding and auto-navigates to home
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();

    // Animation setup
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
      ),
    );

    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
      ),
    );

    // Start animation
    _animationController.forward();

    Future.delayed(const Duration(milliseconds: 2500), () async {
      if (!mounted) return;

      // Sign out any anonymous (guest) user on startup. Guest Mode is
      // temporary and must NOT persist across app restarts â otherwise
      // reopening the app silently resumes guest mode, making it feel
      // like something is forcing the user to stay as guest. Only real
      // (non-anonymous) authenticated sessions should persist.
      final firebaseUser = FirebaseAuth.instance.currentUser;
      if (firebaseUser != null && firebaseUser.isAnonymous) {
        await FirebaseAuth.instance.signOut();
      }

      if (!mounted) return;

      // Use currentUser directly instead of authStateChanges().first.
      // authStateChanges() is a broadcast stream and AuthRepositoryImpl
      // already listens to it. Calling .first after the initial emission
      // misses the event and hangs waiting for the next one. The 2.5s
      // splash delay gives Firebase plenty of time to restore the
      // persisted auth state, so currentUser is reliable here.
      final persistedUser = FirebaseAuth.instance.currentUser;

      if (persistedUser != null && !persistedUser.isAnonymous) {
        // Real authenticated user -> straight to dashboard
        context.go(AppRouter.dashboard);
      } else {
        // No user OR guest (anonymous) -> welcome screen
        // so they can log in, register, or continue as guest
        context.go(AppRouter.welcome);
      }
    });
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    final logoSize =
        MediaQuery.sizeOf(context).shortestSide < 360 ? 104.0 : 124.0;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AppBackground(
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: AppDimensions.paddingLg,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  AnimatedBuilder(
                    animation: _animationController,
                    builder: (context, child) {
                      final animatedChild = Opacity(
                        opacity: reduceMotion ? 1 : _fadeAnimation.value,
                        child: child,
                      );
                      if (reduceMotion) return animatedChild;
                      return Transform.scale(
                        scale: _scaleAnimation.value,
                        child: animatedChild,
                      );
                    },
                    child: Column(
                      children: [
                        Stack(
                          alignment: Alignment.bottomRight,
                          children: [
                            Semantics(
                              image: true,
                              label: '${AppStrings.appName} commuter app logo',
                              child: Container(
                                width: logoSize,
                                height: logoSize,
                                decoration: BoxDecoration(
                                  color: AppColors.surface,
                                  borderRadius: AppDimensions.borderRadiusXl,
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.2),
                                      blurRadius: 20,
                                      offset: const Offset(0, 10),
                                    ),
                                  ],
                                ),
                                child: ClipRRect(
                                  borderRadius: AppDimensions.borderRadiusXl,
                                  child: Image.asset(
                                    'assets/icons/commuter_icon.png',
                                    fit: BoxFit.contain,
                                  ),
                                ),
                              ),
                            ),
                            Container(
                              width: 26,
                              height: 26,
                              decoration: BoxDecoration(
                                color: AppColors.accentRed,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: AppColors.surface,
                                  width: 3,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppDimensions.xl),
                            Text(
                          AppStrings.appName,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.displayLarge
                              ?.copyWith(
                                color: AppColors.textPrimary,
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                        const SizedBox(height: AppDimensions.md),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 360),
                          child: Text(
                            AppStrings.appTagline,
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(
                                  color: AppColors.textSecondary,
                                  height: 1.35,
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
      ),
    );
  }
}
