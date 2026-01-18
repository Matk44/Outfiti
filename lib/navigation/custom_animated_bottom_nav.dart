import 'package:flutter/material.dart';
import 'package:curved_navigation_bar/curved_navigation_bar.dart';
import 'package:provider/provider.dart';
import '../providers/theme_provider.dart';

/// Custom animated bottom navigation bar using curved_navigation_bar
/// This is the fallback implementation used on all platforms except iOS 26+ and macOS 11+
/// Maintains all existing animations and theme integration
class CustomAnimatedBottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const CustomAnimatedBottomNav({
    required this.currentIndex,
    required this.onTap,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    // Get the bottom system UI padding (Android navigation bar height)
    final bottomPadding = MediaQuery.of(context).viewPadding.bottom;

    return Container(
      // Add bottom padding to sit above Android system UI
      padding: EdgeInsets.only(bottom: bottomPadding),
      child: CurvedNavigationBar(
        index: currentIndex,
        items: [
          // Style Me
          Icon(
            Icons.edit,
            size: 30,
            color: currentIndex == 0
                ? (themeProvider.isDarkTheme
                    ? Colors.white
                    : themeProvider.textPrimaryColor)
                : themeProvider.textSecondaryColor,
          ),
          // Wardrobe
          Icon(
            Icons.checkroom,
            size: 30,
            color: currentIndex == 1
                ? (themeProvider.isDarkTheme
                    ? Colors.white
                    : themeProvider.textPrimaryColor)
                : themeProvider.textSecondaryColor,
          ),
          // Copy (outfit copy)
          Icon(
            Icons.dry_cleaning,
            size: 30,
            color: currentIndex == 2
                ? (themeProvider.isDarkTheme
                    ? Colors.white
                    : themeProvider.textPrimaryColor)
                : themeProvider.textSecondaryColor,
          ),
          // Gallery
          Icon(
            Icons.photo_library_outlined,
            size: 30,
            color: currentIndex == 3
                ? (themeProvider.isDarkTheme
                    ? Colors.white
                    : themeProvider.textPrimaryColor)
                : themeProvider.textSecondaryColor,
          ),
          // Profile
          Icon(
            Icons.person,
            size: 30,
            color: currentIndex == 4
                ? (themeProvider.isDarkTheme
                    ? Colors.white
                    : themeProvider.textPrimaryColor)
                : themeProvider.textSecondaryColor,
          ),
        ],
        backgroundColor: Colors.transparent,
        color: themeProvider.surfaceColor,
        buttonBackgroundColor: themeProvider.accentColor,
        animationCurve: Curves.easeInOut,
        animationDuration: const Duration(milliseconds: 400),
        height: 60,
        onTap: onTap,
      ),
    );
  }
}
