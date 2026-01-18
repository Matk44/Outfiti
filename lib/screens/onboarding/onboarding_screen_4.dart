import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../../services/outfit_service.dart';
import '../../services/credit_service.dart';
import '../../widgets/paywall_modal.dart';
import 'onboarding_screen_5.dart';

/// Onboarding Screen 4 - Processing screen with video background and sequential text
/// Shows calm, premium processing animation while generating the hairstyle
///
/// NOTE: This uses FirebaseOnboardingHairstyleService which provides a FREE
/// first generation without consuming any credits. Users will still have
/// their full 2 free credits after completing onboarding.
class OnboardingScreen4 extends StatefulWidget {
  final Uint8List userImage;
  final String description;
  final String targetColor;
  final double aspectRatio;

  const OnboardingScreen4({
    super.key,
    required this.userImage,
    required this.description,
    required this.targetColor,
    this.aspectRatio = 3 / 4,
  });

  @override
  State<OnboardingScreen4> createState() => _OnboardingScreen4State();
}

class _OnboardingScreen4State extends State<OnboardingScreen4> {
  // Use the FREE onboarding service - no credit consumption!
  final DescribeOutfitService _describeService = FirebaseOnboardingOutfitService();

  late VideoPlayerController _videoController;
  bool _videoInitialized = false;

  // Text lines to display sequentially
  final List<String> _textLines = [
    'Analyzing fit and proportions',
    'Aligning garments to your pose',
    'Matching lighting and fabric detail',
  ];

  // Visibility state for each line
  final List<bool> _lineVisibility = [false, false, false];

  // Track which line is currently active/pulsating (-1 = none, 0-2 = line index)
  int _activeLineIndex = -1;

  @override
  void initState() {
    super.initState();
    _initializeVideo();
    _startProcessing();
    _animateTextSequence();
  }

  // Initialize and start video playback
  void _initializeVideo() {
    _videoController = VideoPlayerController.asset('assets/videos/screen4.mp4')
      ..setLooping(true)
      ..setVolume(0.0)
      ..initialize().then((_) {
        if (mounted) {
          setState(() {
            _videoInitialized = true;
          });
          _videoController.play();
        }
      });
  }

  // Animate text lines sequentially
  void _animateTextSequence() {
    // Show first line after brief delay and make it active
    Future.delayed(const Duration(milliseconds: 200), () {
      if (mounted) {
        setState(() {
          _lineVisibility[0] = true;
          _activeLineIndex = 0; // First line is now pulsating
        });
      }
    });

    // Show second line after 2500ms and make it active
    Future.delayed(const Duration(milliseconds: 2500), () {
      if (mounted) {
        setState(() {
          _lineVisibility[1] = true;
          _activeLineIndex = 1; // Second line is now pulsating, first becomes static
        });
      }
    });

    // Show third line after 5000ms and make it active
    Future.delayed(const Duration(milliseconds: 5000), () {
      if (mounted) {
        setState(() {
          _lineVisibility[2] = true;
          _activeLineIndex = 2; // Third line is now pulsating, second becomes static
        });
      }
    });
  }

  Future<void> _startProcessing() async {
    try {
      final result = await _describeService.generateFromDescription(
        selfieImage: widget.userImage,
        userDescription: widget.description,
        targetColor: widget.targetColor,
        aspectRatio: widget.aspectRatio,
      );

      if (mounted) {
        // Navigate to result screen
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => OnboardingScreen5(
              userImage: widget.userImage,
              resultImage: result,
            ),
          ),
        );
      }
    } on OnboardingGenerationUsedException {
      // Free onboarding generation already used - this shouldn't happen during
      // normal onboarding flow, but just in case, show the paywall
      if (mounted) {
        _showInsufficientCreditsDialog(0);
      }
    } on InsufficientCreditsException catch (e) {
      if (mounted) {
        _showInsufficientCreditsDialog(e.currentCredits);
      }
    } on DescribeOutfitException catch (e) {
      if (mounted) {
        _showErrorDialog('Generation failed: ${e.message}');
      }
    } catch (e) {
      if (mounted) {
        _showErrorDialog('An unexpected error occurred: $e');
      }
    }
  }

  void _showInsufficientCreditsDialog(int currentCredits) {
    PaywallModal.show(context);
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Error'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              Navigator.of(context).pop(); // Go back to screen 3
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _videoController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Video background
          if (_videoInitialized)
            Opacity(
              opacity: 0.15,
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: _videoController.value.size.width,
                  height: _videoController.value.size.height,
                  child: VideoPlayer(_videoController),
                ),
              ),
            ),

          // Text overlay
          SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(_textLines.length, (index) {
                    return _AnimatedTextLine(
                      text: _textLines[index],
                      isVisible: _lineVisibility[index],
                      isActive: _activeLineIndex == index,
                    );
                  }),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Widget for individual animated text line with fade, slide, and pulsate animation
class _AnimatedTextLine extends StatefulWidget {
  final String text;
  final bool isVisible;
  final bool isActive;

  const _AnimatedTextLine({
    required this.text,
    required this.isVisible,
    required this.isActive,
  });

  @override
  State<_AnimatedTextLine> createState() => _AnimatedTextLineState();
}

class _AnimatedTextLineState extends State<_AnimatedTextLine>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulsateController;
  late Animation<double> _pulsateAnimation;

  @override
  void initState() {
    super.initState();
    _pulsateController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

    _pulsateAnimation = Tween<double>(begin: 1.0, end: 0.5).animate(
      CurvedAnimation(parent: _pulsateController, curve: Curves.easeInOut),
    );
  }

  @override
  void didUpdateWidget(_AnimatedTextLine oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Start or stop pulsating based on isActive
    if (widget.isActive && !oldWidget.isActive) {
      _pulsateController.repeat(reverse: true);
    } else if (!widget.isActive && oldWidget.isActive) {
      _pulsateController.stop();
      _pulsateController.reset();
    }
  }

  @override
  void dispose() {
    _pulsateController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: widget.isVisible ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeOut,
      child: AnimatedSlide(
        offset: widget.isVisible ? Offset.zero : const Offset(0, 0.15),
        duration: const Duration(milliseconds: 700),
        curve: Curves.easeOut,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14.0),
          child: AnimatedBuilder(
            animation: _pulsateAnimation,
            builder: (context, child) {
              return Opacity(
                opacity: widget.isActive ? _pulsateAnimation.value : 1.0,
                child: child,
              );
            },
            child: Text(
              widget.text,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w400,
                color: Color(0xFFC5A059),
                height: 1.5,
                letterSpacing: 0.3,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}
