import 'package:flutter/cupertino.dart';
import 'package:cupertino_native/cupertino_native.dart';
import 'package:provider/provider.dart';
import '../providers/theme_provider.dart';

/// Native Apple Liquid Glass bottom navigation bar
/// Only used on iOS 14+ and macOS 11+
/// Provides authentic native UI with blur, vibrancy, and system animations
class CupertinoNativeBottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const CupertinoNativeBottomNav({
    required this.currentIndex,
    required this.onTap,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);

    return CNTabBar(
      currentIndex: currentIndex,
      onTap: onTap,
      tint: themeProvider.accentColor,
      items: [
        CNTabBarItem(
          label: 'Style Me',
          icon: CNSymbol('text.bubble'),
        ),
        CNTabBarItem(
          label: 'Wardrobe',
          icon: CNSymbol('hanger'),
        ),
        CNTabBarItem(
          label: 'Copy',
          icon: CNSymbol('tshirt.fill'),
        ),
        CNTabBarItem(
          label: 'Gallery',
          icon: CNSymbol('photo.on.rectangle'),
        ),
        CNTabBarItem(
          label: 'Profile',
          icon: CNSymbol('person.crop.circle'),
        ),
      ],
    );
  }
}
