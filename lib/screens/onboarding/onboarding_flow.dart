import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/theme_provider.dart';
import '../../services/onboarding_service.dart';
import '../../navigation/home_navbar.dart';
import 'onboarding_screen_1.dart';
import 'onboarding_screen_2.dart';
import 'onboarding_screen_3.dart';
// OnboardingScreen4 and OnboardingScreen5 are part of the generation flow
import 'onboarding_screen_6.dart';
import 'onboarding_screen_7.dart';
import 'onboarding_screen_8.dart';

class OnboardingFlow extends StatefulWidget {
  final int initialPage;

  const OnboardingFlow({super.key, this.initialPage = 0});

  @override
  State<OnboardingFlow> createState() => _OnboardingFlowState();
}

class _OnboardingFlowState extends State<OnboardingFlow> {
  late PageController _pageController;
  final OnboardingService _onboardingService = OnboardingService();
  late int _currentPage;
  bool _isCompleting = false;
  double _dragStartX = 0;
  double _dragCurrentX = 0;
  bool _isDragging = false;

  final List<Widget> _screens = const [
    OnboardingScreen1(),
    OnboardingScreen2(),
    OnboardingScreen3(),
    // OnboardingScreen4 and OnboardingScreen5 are now part of the generation flow
    // triggered from OnboardingScreen3 and are not in the PageView
    OnboardingScreen6(),
    OnboardingScreen7(),
    OnboardingScreen8(),
  ];

  @override
  void initState() {
    super.initState();
    _currentPage = widget.initialPage;
    _pageController = PageController(initialPage: widget.initialPage);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _nextPage() {
    if (_currentPage < _screens.length - 1) {
      _pageController.animateToPage(
        _currentPage + 1,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeOutBack, // Bounce effect matching home navigation
      );
    }
  }

  void _previousPage() {
    if (_currentPage > 0) {
      _pageController.animateToPage(
        _currentPage - 1,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeOutBack, // Bounce effect matching home navigation
      );
    }
  }

  Future<void> _completeOnboarding() async {
    setState(() {
      _isCompleting = true;
    });

    try {
      await _onboardingService.completeOnboarding();

      if (mounted) {
        // Navigate to home screen
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const HomeNavBar()),
          (route) => false,
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isCompleting = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to complete onboarding: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isLastPage = _currentPage == _screens.length - 1;
    final isFirstPage = _currentPage == 0;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Full-screen PageView with screens wrapped in gesture detector
          GestureDetector(
            onHorizontalDragStart: (details) {
              _dragStartX = details.globalPosition.dx;
              _dragCurrentX = details.globalPosition.dx;
              _isDragging = true;
            },
            onHorizontalDragUpdate: (details) {
              if (_isDragging) {
                _dragCurrentX = details.globalPosition.dx;
              }
            },
            onHorizontalDragEnd: (details) {
              if (!_isDragging) return;
              _isDragging = false;

              final dragVelocity = details.primaryVelocity ?? 0;
              const velocityThreshold = 500; // Velocity threshold for page change

              // Check velocity first for quick swipes
              // Disable backward navigation starting from screen 6 (index 3)
              if (dragVelocity > velocityThreshold && _currentPage > 0 && _currentPage < 3) {
                // Swipe right - go to previous page
                _previousPage();
              } else if (dragVelocity < -velocityThreshold && _currentPage < _screens.length - 1) {
                // Swipe left - go to next page
                _nextPage();
              } else {
                // Not enough velocity, check drag distance
                final screenWidth = MediaQuery.of(context).size.width;
                final dragDiff = _dragCurrentX - _dragStartX;

                if (dragDiff > screenWidth * 0.3 && _currentPage > 0 && _currentPage < 3) {
                  _previousPage();
                } else if (dragDiff < -screenWidth * 0.3 && _currentPage < _screens.length - 1) {
                  _nextPage();
                }
              }
            },
            child: PageView(
              controller: _pageController,
              physics: const NeverScrollableScrollPhysics(), // Disable default swipe
              onPageChanged: (index) {
                setState(() {
                  _currentPage = index;
                });
              },
              children: _screens,
            ),
          ),

          // Floating page indicator at top
          Positioned(
            top: MediaQuery.of(context).padding.top + 16,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                _screens.length,
                (index) => Container(
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: _currentPage == index ? 32 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4),
                    color: _currentPage == index
                        ? themeProvider.accentColor
                        : (themeProvider.isDarkTheme
                            ? Colors.white.withValues(alpha: 0.3)
                            : Colors.black.withValues(alpha: 0.3)),
                  ),
                ),
              ),
            ),
          ),

          // Floating navigation buttons at bottom (hidden on screens 2, 3, 6, 7, and 8 - profile setup, describe feature, video screen, badge screen, and paywall screen)
          if (_currentPage != 1 && _currentPage != 2 && _currentPage != 3 && _currentPage != 4 && _currentPage != 5)
            Positioned(
              bottom: MediaQuery.of(context).padding.bottom + 24,
              left: 24,
              right: 24,
              child: Row(
                children: [
                  // Back button (hidden on first page and from screen 6 onwards)
                  if (!isFirstPage && _currentPage < 3)
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _previousPage,
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(56),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          side: BorderSide(
                            color: Colors.white.withValues(alpha: 0.5),
                          ),
                          backgroundColor: Colors.black.withValues(alpha: 0.3),
                        ),
                        child: const Text(
                          'Back',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),

                  if (!isFirstPage && _currentPage < 3) const SizedBox(width: 12),

                  // Next/Try it Now/Get Started button
                  Expanded(
                    flex: isFirstPage ? 1 : 1,
                    child: FilledButton(
                      onPressed: _isCompleting
                          ? null
                          : (isLastPage ? _completeOnboarding : _nextPage),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(56),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        backgroundColor: themeProvider.accentColor,
                      ),
                      child: _isCompleting
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(
                              isLastPage ? 'Get Started' : (isFirstPage ? 'Try it now' : 'Next'),
                              style: TextStyle(
                                color: ThemeData.estimateBrightnessForColor(themeProvider.accentColor) == Brightness.light
                                    ? Colors.black
                                    : Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
