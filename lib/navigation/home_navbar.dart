import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'adaptive_bottom_navigation.dart';
import '../screens/outfit_try_on_screen.dart';
import '../screens/ai_try_on_screen.dart'; // AI Try-On screen
import '../screens/describe_screen.dart';
import '../screens/gallery_screen.dart';
import '../screens/profile_screen.dart';
import '../widgets/profile_circle_button.dart';
import '../providers/theme_provider.dart';

/// Custom page controller with bounce effect for screen transitions
class _BouncePageController extends PageController {
  _BouncePageController({super.initialPage});
}

/// Home navigation widget with adaptive bottom navigation bar
/// Uses native Liquid Glass on iOS 14+ and macOS 11+, custom animated nav elsewhere
/// Provides tab navigation between Describe, Color, Copy, Gallery, and Profile screens
class HomeNavBar extends StatefulWidget {
  const HomeNavBar({super.key});

  @override
  State<HomeNavBar> createState() => _HomeNavBarState();
}

class _HomeNavBarState extends State<HomeNavBar> {
  int _selectedIndex = 0;
  late _BouncePageController _pageController;

  @override
  void initState() {
    super.initState();
    _pageController = _BouncePageController(initialPage: _selectedIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  // Screen widgets for each tab (reordered: Describe, Style, Copy, Gallery, Profile)
  final List<Widget> _screens = const [
    DescribeScreen(),
    AITryOnScreen(),
    OutfitTryOnScreen(),
    GalleryScreen(),
    ProfileScreen(),
  ];

  // Screen metadata (title and subtitle for each tab)
  final List<Map<String, String>> _screenMetadata = const [
    {
      'title': 'Style Me',
      'subtitle': 'Describe the vibe. We’ll style you.',
    },
    {
      'title': 'Style With Any Clothes',
      'subtitle': 'Upload clothing items. We’ll style them on you as one complete outfit.',
    },
    {
      'title': 'Copy an Outfit',
      'subtitle': 'Use a reference image to see it on you.',
    },
    {
      'title': 'Your Creations',
      'subtitle': 'Browse your recent outfit try-ons.',
    },
    {
      'title': 'Profile',
      'subtitle': 'Settings & preferences',
    },
  ];

  @override
  Widget build(BuildContext context) {
    final showAppBar = _selectedIndex != 4; // Don't show on ProfileScreen (index 4)
    final themeProvider = Provider.of<ThemeProvider>(context);
    final colorScheme = Theme.of(context).colorScheme;

    // System UI overlay style based on theme brightness
    final systemUiOverlayStyle = SystemUiOverlayStyle(
      statusBarBrightness: themeProvider.isDarkTheme ? Brightness.dark : Brightness.light,
      statusBarIconBrightness: themeProvider.isDarkTheme ? Brightness.light : Brightness.dark,
      systemNavigationBarColor: colorScheme.surface,
      systemNavigationBarIconBrightness: themeProvider.isDarkTheme ? Brightness.light : Brightness.dark,
    );

    return Scaffold(
      extendBody: true, // Allow the curve to float over body
      appBar: showAppBar
          ? PreferredSize(
              preferredSize: const Size.fromHeight(84),
              child: AppBar(
                backgroundColor: Colors.transparent,
                elevation: 0,
                automaticallyImplyLeading: false,
                systemOverlayStyle: systemUiOverlayStyle,
                flexibleSpace: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Left-aligned Title and Subtitle
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _screenMetadata[_selectedIndex]['title']!,
                                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 18,
                                    ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _screenMetadata[_selectedIndex]['subtitle']!,
                                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                      color: Theme.of(context).colorScheme.outline,
                                      fontSize: 11,
                                      height: 1.3,
                                    ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Profile Circle Button with Credits (positioned on right)
                        GestureDetector(
                          onTap: () {
                            _pageController.animateToPage(
                              4, // Navigate to ProfileScreen (index 4)
                              duration: const Duration(milliseconds: 500),
                              curve: Curves.easeOutBack,
                            );
                          },
                          child: ProfileCircleButton(showCredits: true),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            )
          : null,
      bottomNavigationBar: AdaptiveBottomNavigation(
        currentIndex: _selectedIndex,
        onTap: (index) {
          _pageController.animateToPage(
            index,
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeOutBack, // Smooth with subtle bounce at the end
          );
        },
      ),
      body: PageView(
        controller: _pageController,
        physics: const NeverScrollableScrollPhysics(), // Disable swipe navigation
        onPageChanged: (index) {
          setState(() {
            _selectedIndex = index;
          });
        },
        children: _screens,
      ),
    );
  }
}
