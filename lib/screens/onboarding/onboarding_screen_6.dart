import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:provider/provider.dart';
import '../../providers/theme_provider.dart';

class OnboardingScreen6 extends StatefulWidget {
  const OnboardingScreen6({super.key});

  @override
  State<OnboardingScreen6> createState() => _OnboardingScreen6State();
}

class _OnboardingScreen6State extends State<OnboardingScreen6> {
  late VideoPlayerController _videoController;
  bool _videoInitialized = false;
  int _currentTextIndex = 0; // 0, 1, or 2 for the three text phases

  @override
  void initState() {
    super.initState();
    _initializeVideo();
  }

  void _initializeVideo() {
    _videoController = VideoPlayerController.asset('assets/videos/screen6.mov')
      ..setLooping(true)
      ..setVolume(0.0)
      ..initialize().then((_) {
        if (mounted) {
          setState(() {
            _videoInitialized = true;
          });
          _videoController.play();

          // Listen to video position to update text
          _videoController.addListener(_onVideoPositionChanged);
        }
      });
  }

  void _onVideoPositionChanged() {
    if (!mounted) return;

    final position = _videoController.value.position.inSeconds;
    int newIndex;

    if (position < 13) {
      newIndex = 0; // First text: 0-12 seconds
    } else if (position < 24) {
      newIndex = 1; // Second text: 13-23 seconds
    } else {
      newIndex = 2; // Third text: 24+ seconds
    }

    if (newIndex != _currentTextIndex) {
      setState(() {
        _currentTextIndex = newIndex;
      });
    }
  }

  @override
  void dispose() {
    _videoController.removeListener(_onVideoPositionChanged);
    _videoController.dispose();
    super.dispose();
  }

  Widget _buildTextContent() {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final theme = Theme.of(context);

    switch (_currentTextIndex) {
      case 0:
        return Text(
          'See an outfit you love? Wear it.',
          style: theme.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w500,
            color: themeProvider.textPrimaryColor,
            height: 1.4,
          ),
          textAlign: TextAlign.center,
        );
      case 1:
        return Text(
          'Tailor the look. Instantly.',
          style: theme.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w500,
            color: themeProvider.textPrimaryColor,
            height: 1.4,
          ),
          textAlign: TextAlign.center,
        );
      case 2:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '“I stopped guessing what to wear.”',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w400,
                color: themeProvider.textPrimaryColor,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            Text(
              '“I bought the outfit after this.”',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w400,
                color: themeProvider.textPrimaryColor,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        );
      default:
        return const SizedBox.shrink();
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);

    return Scaffold(
      backgroundColor: themeProvider.backgroundColor,
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                const SizedBox(height: 70), // Push video down to avoid app bar and swipe hint

                // Video section - 3/4 of screen
                Expanded(
                  flex: 3,
                  child: Center(
                    child: _videoInitialized
                        ? IgnorePointer(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(20),
                              child: AspectRatio(
                                aspectRatio: _videoController.value.aspectRatio,
                                child: VideoPlayer(_videoController),
                              ),
                            ),
                          )
                        : const CircularProgressIndicator(),
                  ),
                ),

                // Text section - 1/4 of screen
                Expanded(
                  flex: 1,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32.0),
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 600),
                        switchInCurve: Curves.easeOut,
                        switchOutCurve: Curves.easeIn,
                        transitionBuilder: (Widget child, Animation<double> animation) {
                          return FadeTransition(
                            opacity: animation,
                            child: SlideTransition(
                              position: Tween<Offset>(
                                begin: const Offset(0, 0.1),
                                end: Offset.zero,
                              ).animate(animation),
                              child: child,
                            ),
                          );
                        },
                        child: Container(
                          key: ValueKey<int>(_currentTextIndex),
                          child: _buildTextContent(),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),

            // Swipe gesture indicator - below page dots
            Positioned(
              top: 48,
              left: 0,
              right: 0,
              child: IgnorePointer(
                child: Center(
                  child: _SwipeGestureIndicator(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Animated swipe gesture indicator
class _SwipeGestureIndicator extends StatefulWidget {
  @override
  State<_SwipeGestureIndicator> createState() => _SwipeGestureIndicatorState();
}

class _SwipeGestureIndicatorState extends State<_SwipeGestureIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _offsetAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    )..repeat(reverse: true);

    _offsetAnimation = Tween<Offset>(
      begin: Offset.zero,
      end: const Offset(0.2, 0),
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeInOut,
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);

    return SlideTransition(
      position: _offsetAnimation,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Swipe',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w400,
              color: themeProvider.textSecondaryColor.withValues(alpha: 0.6),
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(width: 4),
          Icon(
            Icons.arrow_forward_ios,
            size: 14,
            color: themeProvider.textSecondaryColor.withValues(alpha: 0.6),
          ),
        ],
      ),
    );
  }
}
