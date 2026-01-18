import 'package:flutter/material.dart';
import '../utils/platform_detection.dart';
import 'cupertino_native_bottom_nav.dart';
import 'custom_animated_bottom_nav.dart';

/// Adaptive bottom navigation that conditionally uses platform-specific implementations
///
/// Platform behavior:
/// - iOS 14+: Native Liquid Glass navigation (cupertino_native)
/// - macOS 11+: Native Liquid Glass navigation (cupertino_native)
/// - All other platforms/versions: Custom animated navigation bar (curved_navigation_bar)
///
/// This widget abstracts the platform detection and selection logic,
/// ensuring the app always uses the appropriate navigation implementation
/// without manual platform checks.
class AdaptiveBottomNavigation extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const AdaptiveBottomNavigation({
    required this.currentIndex,
    required this.onTap,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: PlatformDetection.shouldUseCupertinoNative(),
      builder: (context, snapshot) {
        // Use native implementation only if explicitly supported
        final useNative = snapshot.data ?? false;

        if (useNative) {
          return CupertinoNativeBottomNav(
            currentIndex: currentIndex,
            onTap: onTap,
          );
        }

        // Default fallback: custom animated navigation
        return CustomAnimatedBottomNav(
          currentIndex: currentIndex,
          onTap: onTap,
        );
      },
    );
  }
}
