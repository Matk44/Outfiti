import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:gal/gal.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../providers/gallery_refresh_notifier.dart';
import '../services/outfit_service.dart';
import '../services/credit_service.dart';
import '../services/user_profile_service.dart';
import '../services/review_prompt_service.dart';
import '../widgets/paywall_modal.dart';
import '../widgets/credit_topup_modal.dart';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';

/// Outfit Try On screen - Main feature for trying on different outfits
class OutfitTryOnScreen extends StatefulWidget {
  const OutfitTryOnScreen({super.key});

  @override
  State<OutfitTryOnScreen> createState() => _OutfitTryOnScreenState();
}

class _OutfitTryOnScreenState extends State<OutfitTryOnScreen>
    with SingleTickerProviderStateMixin {
  // State management
  Uint8List? referenceImage;
  Uint8List? selfieImage;
  Uint8List? resultImage;
  bool isAnimating = false;
  bool showResult = false;
  String? errorMessage;
  double _sliderPosition = 0.75; // Start at 3/4 to tease the reveal
  bool _hasUserInteracted = false; // Track if user has started sliding
  bool _isResultSaved = false; // Track if current result has been saved
  bool _isSelfieRealImage = false; // Track if selfie is real upload or placeholder
  bool _isReferenceRealImage = false; // Track if reference is real upload or placeholder
  bool _isLoadingProfileImage = false; // Track if loading profile image
  double _imageAspectRatio = 3 / 4; // Default aspect ratio (width/height)

  // Placeholder image rotation
  List<Uint8List> _referencePlaceholders = [];
  List<Uint8List> _selfiePlaceholders = [];
  int _currentPlaceholderIndex = 0;
  Timer? _placeholderRotationTimer;

  // Rotating tips for angle matching
  final List<String> _angleTips = [
    'If the reference is a side view, use a side-view photo of you.',
    'Front view → Front photo of you',
    'Side view → Side photo of you',
    'Similar angle = cleaner result',
  ];
  int _currentTipIndex = 0;
  Timer? _tipRotationTimer;

  // Animation controller for reveal
  late AnimationController _revealController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;

  final ImagePicker _picker = ImagePicker();
  final OutfitService _outfitService = FirebaseOutfitService();
  final CreditService _creditService = CreditService();
  final UserProfileService _profileService = UserProfileService();

  bool get canGenerate => referenceImage != null && selfieImage != null && _isSelfieRealImage && _isReferenceRealImage;

  @override
  void initState() {
    super.initState();
    _revealController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _scaleAnimation = Tween<double>(begin: 0.95, end: 1.0).animate(
      CurvedAnimation(parent: _revealController, curve: Curves.easeOutCubic),
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _revealController, curve: Curves.easeOut),
    );
    _loadPlaceholderImage();
    _startPlaceholderRotation();
    _startTipRotation();
  }

  // Load placeholder images for reference and selfie
  Future<void> _loadPlaceholderImage() async {
    try {
      // Load all placeholder image sets (front, angle, side)
      final referenceFront = await rootBundle.load('assets/icons/reference_placeholder.png');
      final referenceAngle = await rootBundle.load('assets/icons/reference_angle.png');
      final referenceSide = await rootBundle.load('assets/icons/reference_side.png');

      final selfieFront = await rootBundle.load('assets/icons/selfie_placeholder.png');
      final selfieAngle = await rootBundle.load('assets/icons/selfie_angle.png');
      final selfieSide = await rootBundle.load('assets/icons/selfie_side.png');

      setState(() {
        _referencePlaceholders = [
          referenceFront.buffer.asUint8List(),
          referenceAngle.buffer.asUint8List(),
          referenceSide.buffer.asUint8List(),
        ];
        _selfiePlaceholders = [
          selfieFront.buffer.asUint8List(),
          selfieAngle.buffer.asUint8List(),
          selfieSide.buffer.asUint8List(),
        ];

        // Set initial placeholder images
        referenceImage = _referencePlaceholders[0];
        selfieImage = _selfiePlaceholders[0];
        _isReferenceRealImage = false;
        _isSelfieRealImage = false;
      });
    } catch (e) {
      // If placeholder fails to load, just skip it
      print('Failed to load placeholder: $e');
    }
  }

  // Start rotating placeholder images every 3 seconds
  void _startPlaceholderRotation() {
    _placeholderRotationTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      // Only rotate if user hasn't uploaded real images
      if (!_isReferenceRealImage && !_isSelfieRealImage && mounted) {
        setState(() {
          _currentPlaceholderIndex = (_currentPlaceholderIndex + 1) % _referencePlaceholders.length;
          if (_referencePlaceholders.isNotEmpty && _selfiePlaceholders.isNotEmpty) {
            referenceImage = _referencePlaceholders[_currentPlaceholderIndex];
            selfieImage = _selfiePlaceholders[_currentPlaceholderIndex];
          }
        });
      }
    });
  }

  // Start rotating angle tips every 4 seconds
  void _startTipRotation() {
    _tipRotationTimer = Timer.periodic(const Duration(seconds: 4), (timer) {
      if (mounted && !showResult) {
        setState(() {
          _currentTipIndex = (_currentTipIndex + 1) % _angleTips.length;
        });
      }
    });
  }

  @override
  void dispose() {
    _revealController.dispose();
    _placeholderRotationTimer?.cancel();
    _tipRotationTimer?.cancel();
    super.dispose();
  }

  // Calculate aspect ratio from image bytes
  Future<double> _calculateAspectRatio(Uint8List imageBytes) async {
    try {
      final codec = await ui.instantiateImageCodec(imageBytes);
      final frame = await codec.getNextFrame();
      final image = frame.image;
      final aspectRatio = image.width / image.height;
      image.dispose();
      codec.dispose();
      return aspectRatio;
    } catch (e) {
      debugPrint('Error calculating aspect ratio: $e');
      return 3 / 4; // Default aspect ratio on error
    }
  }

  // Pick image from gallery
  Future<void> _pickImage(bool isReference) async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      );

      if (image != null) {
        final bytes = await image.readAsBytes();

        // Calculate aspect ratio for selfie images (base for output)
        double? aspectRatio;
        if (!isReference) {
          aspectRatio = await _calculateAspectRatio(bytes);
        }

        setState(() {
          if (isReference) {
            referenceImage = bytes;
            _isReferenceRealImage = true; // Mark as real image
          } else {
            selfieImage = bytes;
            _isSelfieRealImage = true; // Mark as real image
            if (aspectRatio != null) {
              _imageAspectRatio = aspectRatio;
            }
          }
          // Reset result state when new image is uploaded
          showResult = false;
          resultImage = null;
          errorMessage = null;
          _hasUserInteracted = false;
          _sliderPosition = 0.75;
          _isResultSaved = false;
        });
        _revealController.reset();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error picking image: $e')),
        );
      }
    }
  }

  // Load profile image from URL
  Future<void> _loadProfileImage(String profileImageUrl, bool isReference) async {
    // Haptic feedback
    HapticFeedback.lightImpact();

    setState(() {
      _isLoadingProfileImage = true;
    });

    try {
      final response = await http.get(Uri.parse(profileImageUrl));
      if (response.statusCode == 200) {
        final bytes = response.bodyBytes;

        // Calculate aspect ratio for selfie images (base for output)
        double? aspectRatio;
        if (!isReference) {
          aspectRatio = await _calculateAspectRatio(bytes);
        }

        if (mounted) {
          setState(() {
            if (isReference) {
              referenceImage = bytes;
              _isReferenceRealImage = true;
            } else {
              selfieImage = bytes;
              _isSelfieRealImage = true;
              if (aspectRatio != null) {
                _imageAspectRatio = aspectRatio;
              }
            }
            // Reset result state when new image is loaded
            showResult = false;
            resultImage = null;
            errorMessage = null;
            _hasUserInteracted = false;
            _sliderPosition = 0.75;
            _isResultSaved = false;
            _isLoadingProfileImage = false;
          });
          _revealController.reset();
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingProfileImage = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading profile image: $e')),
        );
      }
    }
  }

  // Generate hairstyle using AI
  Future<void> _generateTryOn() async {
    if (!canGenerate) return;

    // Check credits BEFORE attempting generation
    try {
      final userCredits = await _creditService.getCredits();

      // If credits are 0, show appropriate modal
      if (userCredits.credits == 0) {
        if (!mounted) return;

        // Determine if user is pro
        final isPro = userCredits.plan != UserPlan.free;

        if (isPro) {
          // Pro user → show credit top-up modal
          await CreditTopUpModal.show(context);
        } else {
          // Free user → show full paywall
          await PaywallModal.show(context);
        }

        return; // Stop execution
      }
    } catch (e) {
      debugPrint('Error checking credits: $e');
      // Continue to generation - server will handle if error occurred
    }

    setState(() {
      isAnimating = true;
      showResult = false;
      errorMessage = null;
    });

    try {
      final result = await _outfitService.generateOutfit(
        selfieImage: selfieImage!,
        referenceImage: referenceImage!,
        aspectRatio: _imageAspectRatio,
      );

      // Debug: Log result size and compare with input
      print('=== RESULT IMAGE DEBUG ===');
      print('Result image size: ${result.length} bytes');
      print('Selfie image size: ${selfieImage!.length} bytes');
      print('Reference image size: ${referenceImage!.length} bytes');

      // Check if result is identical to selfie (which would indicate a problem)
      bool isSameAsSelfie = result.length == selfieImage!.length;
      if (isSameAsSelfie) {
        // Do a more thorough check - compare first 100 bytes
        int sameBytes = 0;
        for (int i = 0; i < 100 && i < result.length; i++) {
          if (result[i] == selfieImage![i]) sameBytes++;
        }
        isSameAsSelfie = sameBytes > 90; // If more than 90% same, likely identical
        print('Bytes comparison (first 100): $sameBytes/100 match');
      }

      if (isSameAsSelfie) {
        print('WARNING: Result appears identical to selfie input!');
      }
      print('=== END RESULT DEBUG ===');

      if (mounted) {
        setState(() {
          resultImage = result;
          showResult = true;
          isAnimating = false;
          _hasUserInteracted = false; // Reset for new result
          _sliderPosition = 0.75; // Position at 3/4 for reveal
          _isResultSaved = false; // New result is not saved yet
        });

        // Trigger reveal animation
        _revealController.forward();
      }
    } on InsufficientCreditsException catch (e) {
      if (mounted) {
        setState(() {
          isAnimating = false;
          errorMessage = 'Insufficient credits';
        });
        _showInsufficientCreditsDialog(e.currentCredits);
      }
    } on RateLimitCooldownException {
      // Rate limited - show friendly message without exposing cooldown details
      if (mounted) {
        setState(() {
          isAnimating = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Please wait a moment before trying again'),
            backgroundColor: Theme.of(context).colorScheme.secondary,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } on ConcurrentLimitException {
      // Too many concurrent requests
      if (mounted) {
        setState(() {
          isAnimating = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Processing in progress. Please wait...'),
            backgroundColor: Theme.of(context).colorScheme.secondary,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } on OutfitGenerationException catch (e) {
      if (mounted) {
        setState(() {
          isAnimating = false;
          errorMessage = e.message;
        });
        // Log error for debugging
        print('OutfitGenerationException: ${e.message}');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Generation failed: ${e.message}'),
            backgroundColor: Theme.of(context).colorScheme.error,
            duration: const Duration(seconds: 10),
            action: SnackBarAction(
              label: 'Details',
              textColor: Colors.white,
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Error Details'),
                    content: SingleChildScrollView(
                      child: Text(e.message),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('OK'),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        );
      }
    } catch (e, stackTrace) {
      if (mounted) {
        setState(() {
          isAnimating = false;
          errorMessage = e.toString();
        });
        // Log error for debugging
        print('Error in _generateTryOn: $e');
        print('Stack trace: $stackTrace');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
            duration: const Duration(seconds: 10),
          ),
        );
      }
    }
  }

  // Save result image to gallery
  Future<void> _saveToGallery() async {
    if (resultImage == null) return;

    try {
      // Save image to HairTryOn album for easy gallery retrieval
      await Gal.putImageBytes(resultImage!, album: 'Outfiti');

      if (mounted) {
        setState(() {
          _isResultSaved = true;
        });
        // Trigger gallery refresh so new image appears immediately
        context.read<GalleryRefreshNotifier>().triggerRefresh();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Image saved to gallery successfully!'),
            backgroundColor: Theme.of(context).colorScheme.secondary,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save image: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  // Share result image
  Future<void> _shareResult() async {
    if (resultImage == null) return;

    try {
      // Create a temporary file from the result image bytes
      final tempDir = await Directory.systemTemp.createTemp('outfiti_');
      final file = File('${tempDir.path}/outfit_result.jpg');
      await file.writeAsBytes(resultImage!);

      // Get the screen size for iPad popover positioning
      final box = context.findRenderObject() as RenderBox?;
      final sharePositionOrigin = box != null
          ? box.localToGlobal(Offset.zero) & box.size
          : null;

      await Share.shareXFiles(
        [XFile(file.path)],
        text: 'Check out my outfit created by Outfiti! https://apps.apple.com/us/app/outfiti/id6757889234',
        sharePositionOrigin: sharePositionOrigin,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to share image: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  // Show confirmation dialog when user tries to navigate away with unsaved result
  Future<bool> _onWillPop() async {
    // Block navigation during generation - user would lose their credit
    if (isAnimating) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Please wait for generation to complete. Leaving now will waste your credit.',
          ),
          backgroundColor: Theme.of(context).colorScheme.error,
          duration: const Duration(seconds: 3),
        ),
      );
      return false;
    }

    // Try to show review prompt when navigating away from result
    try {
      final reviewService =
          Provider.of<ReviewPromptService>(context, listen: false);
      await reviewService.tryShowReview();
    } catch (e) {
      debugPrint('Error showing review prompt: $e');
    }

    // If there's no result or it's already saved, allow navigation
    if (resultImage == null || _isResultSaved) {
      return true;
    }

    // Show confirmation dialog
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Unsaved Result'),
        content: const Text(
          'You have an unsaved outfit result. Would you like to save it before leaving?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false), // Discard
            child: Text(
              'Discard',
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, null), // Cancel
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              await _saveToGallery();
              if (ctx.mounted) {
                Navigator.pop(ctx, true); // Save and leave
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );

    // null means cancel, don't navigate
    // true means saved, can navigate
    // false means discard, can navigate
    return result ?? false;
  }

  // Check before resetting result (Try Again button)
  Future<void> _handleTryAgain() async {
    if (resultImage != null && !_isResultSaved) {
      final shouldProceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Unsaved Result'),
          content: const Text(
            'You have an unsaved outfit result. Would you like to save it before trying again?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, true), // Discard
              child: Text(
                'Discard',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, false), // Cancel
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                await _saveToGallery();
                if (ctx.mounted) {
                  Navigator.pop(ctx, true); // Save and proceed
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      );

      if (shouldProceed != true) return;
    }

    setState(() {
      showResult = false;
      resultImage = null;
      _isResultSaved = false;
    });
  }

  // Show insufficient credits dialog - opens paywall
  void _showInsufficientCreditsDialog(int currentCredits) {
    PaywallModal.show(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, dynamic result) async {
        if (didPop) return;
        final shouldPop = await _onWillPop();
        if (shouldPop && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        backgroundColor: colorScheme.surface,
        body: SafeArea(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 400),
            child: showResult && resultImage != null
                ? _buildResultView(theme, colorScheme)
                : _buildUploadView(theme, colorScheme),
          ),
        ),
      ),
    );
  }

  // Upload view with hero and side-by-side cards
  Widget _buildUploadView(ThemeData theme, ColorScheme colorScheme) {
    return Stack(
      key: const ValueKey('upload'),
      children: [
        // Main content
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 16),

              // Hero Section - Headline
              _buildHeroSection(theme, colorScheme),

              const SizedBox(height: 32),

              // Side-by-side Image Cards
              Expanded(
                child: _buildImageCardsSection(theme, colorScheme),
              ),

              const SizedBox(height: 24),

              // Refinement Tip
              _buildRefinementTip(theme, colorScheme),

              const SizedBox(height: 100), // Space for floating button
            ],
          ),
        ),

        // Floating Bottom CTA
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: _buildFloatingBottomCTA(theme, colorScheme),
        ),
      ],
    );
  }

  // Hero section with elegant headline
  Widget _buildHeroSection(ThemeData theme, ColorScheme colorScheme) {
    return Column(
      children: [
        Text(
          'Love the Look?',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.w500,
            color: colorScheme.onSurface,
            height: 1.2,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: ShaderMask(
            shaderCallback: (bounds) => LinearGradient(
              colors: [
                colorScheme.secondary,
                const Color(0xFFD4AF37),
                colorScheme.secondary,
              ],
            ).createShader(bounds),
            child: Text(
              'Try It On',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w600,
                fontStyle: FontStyle.italic,
                color: Colors.white,
                height: 1.2,
                letterSpacing: 0,
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Use a reference image to see it on you.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w300,
            color: colorScheme.onSurfaceVariant,
            height: 1.5,
          ),
        ),
      ],
    ).animate().fadeIn(duration: 600.ms).slideY(
          begin: -0.05,
          end: 0,
          duration: 600.ms,
          curve: Curves.easeOut,
        );
  }

  // Image cards section with side-by-side layout
  Widget _buildImageCardsSection(ThemeData theme, ColorScheme colorScheme) {
    return Stack(
      children: [
        // Decorative divider line
        Positioned(
          top: 0,
          bottom: 0,
          left: 0,
          right: 0,
          child: Center(
            child: Container(
              height: 1,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.transparent,
                    colorScheme.secondary.withValues(alpha: 0.3),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
        ),
        // Image cards
        Row(
          children: [
            Expanded(
              child: Column(
                children: [
                  Text(
                    'REFERENCE',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2,
                      color: colorScheme.secondary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Outfit & pose',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w400,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _buildImageCard(
                    image: referenceImage,
                    icon: Icons.auto_awesome,
                    colorScheme: colorScheme,
                    onTap: () => _pickImage(true),
                    isRealImage: _isReferenceRealImage,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 20),
            // Center plus icon with microcopy
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: colorScheme.surface,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: colorScheme.outline.withValues(alpha: 0.1),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: colorScheme.secondary.withValues(alpha: 0.1),
                        blurRadius: 12,
                      ),
                    ],
                  ),
                  child: Icon(
                    Icons.add,
                    color: colorScheme.secondary,
                    size: 24,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Same angle\nworks best',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 8,
                    fontWeight: FontWeight.w500,
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                    height: 1.3,
                  ),
                ),
              ],
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                children: [
                  Text(
                    'YOUR PHOTO',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2,
                      color: colorScheme.secondary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Your photo, same angle',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w400,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _buildImageCard(
                    image: selfieImage,
                    icon: Icons.face,
                    colorScheme: colorScheme,
                    onTap: () => _pickImage(false),
                    isRealImage: _isSelfieRealImage,
                  ),
                  const SizedBox(height: 2),
                  // Use Profile Photo toggle - minimal version
                  Builder(
                    builder: (context) {
                      final stream = _profileService.getUserProfileStream();
                      if (stream == null) return const SizedBox.shrink();

                      return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                        stream: stream,
                        builder: (context, snapshot) {
                          final profileData = snapshot.data?.data();
                          final profileImageUrl = profileData?['profileImageUrl'] ?? '';

                          // Only show if profile image exists
                          if (profileImageUrl.isEmpty) {
                            return const SizedBox.shrink();
                          }

                          return Column(
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.account_circle,
                                    size: 9,
                                    color: colorScheme.secondary,
                                  ),
                                  const SizedBox(width: 2),
                                  Flexible(
                                    child: Text(
                                      'Use Profile Pic',
                                      style: TextStyle(
                                        fontSize: 8,
                                        fontWeight: FontWeight.w500,
                                        color: colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 1),
                                  if (_isLoadingProfileImage)
                                    SizedBox(
                                      width: 10,
                                      height: 10,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 1.5,
                                        color: colorScheme.secondary,
                                      ),
                                    )
                                  else
                                    Transform.scale(
                                      scale: 0.6,
                                      child: Switch(
                                        value: _isSelfieRealImage,
                                        onChanged: (value) {
                                          if (value && !_isLoadingProfileImage) {
                                            _loadProfileImage(profileImageUrl, false);
                                          }
                                        },
                                        activeTrackColor: colorScheme.secondary,
                                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          );
                        },
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    ).animate().fadeIn(duration: 600.ms, delay: 100.ms);
  }

  // Individual image card with elegant design
  Widget _buildImageCard({
    required Uint8List? image,
    required IconData icon,
    required ColorScheme colorScheme,
    required VoidCallback onTap,
    required bool isRealImage,
  }) {
    final hasImage = image != null;

    return GestureDetector(
      onTap: onTap,
      child: AspectRatio(
        aspectRatio: 3 / 4,
        child: Container(
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: hasImage
                  ? colorScheme.secondary.withValues(alpha: 0.5)
                  : colorScheme.outline.withValues(alpha: 0.2),
              width: 1,
            ),
            boxShadow: hasImage
                ? [
                    BoxShadow(
                      color: colorScheme.secondary.withValues(alpha: 0.15),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ]
                : null,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(23),
            child: Stack(
              children: [
                if (hasImage)
                  Positioned.fill(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 600),
                      switchInCurve: Curves.easeInOut,
                      switchOutCurve: Curves.easeInOut,
                      layoutBuilder: (currentChild, previousChildren) {
                        return Stack(
                          fit: StackFit.expand,
                          children: <Widget>[
                            ...previousChildren,
                            if (currentChild != null) currentChild,
                          ],
                        );
                      },
                      child: Image.memory(
                        image,
                        key: ValueKey(isRealImage ? 'real-${image.hashCode}' : 'placeholder-$_currentPlaceholderIndex'),
                        fit: BoxFit.cover,
                        width: double.infinity,
                        height: double.infinity,
                      ),
                    ),
                  )
                else
                  Positioned.fill(
                    child: Container(
                      color: colorScheme.surface,
                    ),
                  ),

                // Gradient overlay for images
                if (hasImage)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Container(
                      height: 100,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.6),
                          ],
                        ),
                      ),
                    ),
                  ),

                // Edit button for all cards (bottom-right)
                if (hasImage)
                  Positioned(
                    bottom: 12,
                    right: 12,
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.4),
                          width: 1.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.15),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.edit,
                        size: 16,
                        color: Colors.white,
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

  // Refinement tip section with rotating angle tips
  Widget _buildRefinementTip(ThemeData theme, ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFF9F5EB).withValues(alpha: 0.3),
        border: Border.all(
          color: colorScheme.secondary.withValues(alpha: 0.2),
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: colorScheme.secondary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.auto_awesome,
              size: 18,
              color: colorScheme.secondary,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'ANGLE MATCH TIP',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2,
                    color: colorScheme.secondary,
                  ),
                ),
                const SizedBox(height: 4),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 400),
                  switchInCurve: Curves.easeInOut,
                  switchOutCurve: Curves.easeInOut,
                  transitionBuilder: (child, animation) {
                    return FadeTransition(
                      opacity: animation,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0, 0.2),
                          end: Offset.zero,
                        ).animate(animation),
                        child: child,
                      ),
                    );
                  },
                  child: Text(
                    _angleTips[_currentTipIndex],
                    key: ValueKey(_currentTipIndex),
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.onSurfaceVariant,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 600.ms, delay: 200.ms);
  }


  // Floating bottom CTA with gradient button
  Widget _buildFloatingBottomCTA(ThemeData theme, ColorScheme colorScheme) {
    return StreamBuilder<UserCredits>(
      stream: _creditService.creditsStream,
      builder: (context, snapshot) {
        final currentCredits = snapshot.data?.credits ?? 0;
        final hasCredits = currentCredits > 0;

        // Update button text based on credits
        final buttonText = hasCredits ? 'Try This Look On Me' : 'Credits';
        final buttonIcon = hasCredits ? Icons.auto_fix_high : Icons.add_circle_outline;

        return Padding(
          padding: const EdgeInsets.all(24),
          child: Container(
            width: double.infinity,
            height: 56,
            decoration: BoxDecoration(
              color: canGenerate && !isAnimating
                  ? colorScheme.secondary
                  : colorScheme.onSurface.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: canGenerate && !isAnimating ? _generateTryOn : null,
                borderRadius: BorderRadius.circular(12),
                child: Center(
                  child: isAnimating
                      ? SizedBox(
                          height: 24,
                          width: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Colors.white,
                          ),
                        )
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              buttonIcon,
                              size: 20,
                              color: canGenerate ? Colors.white : colorScheme.onSurface.withValues(alpha: 0.38),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              buttonText,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.5,
                                color: canGenerate ? Colors.white : colorScheme.onSurface.withValues(alpha: 0.38),
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // Result view with elegant styling
  Widget _buildResultView(ThemeData theme, ColorScheme colorScheme) {
    return Column(
      key: const ValueKey('result'),
      children: [
        // Share button (top-right) - compact
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              IconButton(
                onPressed: _shareResult,
                icon: Icon(
                  Icons.ios_share,
                  size: 20,
                  color: colorScheme.secondary,
                ),
                tooltip: 'Share',
                visualDensity: VisualDensity.compact,
                style: IconButton.styleFrom(
                  backgroundColor: colorScheme.secondary.withValues(alpha: 0.1),
                  padding: const EdgeInsets.all(8),
                ),
              ),
            ],
          ),
        ),

        // Result image with before/after slider - takes remaining space
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(2),
                boxShadow: [
                  BoxShadow(
                    color: colorScheme.secondary.withValues(alpha: 0.15),
                    blurRadius: 40,
                    offset: const Offset(0, 10),
                  ),
                ],
                border: Border.all(
                  color: colorScheme.outline.withValues(alpha: 0.1),
                  width: 4,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(0),
                child: AnimatedBuilder(
                  animation: _revealController,
                  builder: (context, child) {
                    return Transform.scale(
                      scale: _scaleAnimation.value,
                      child: Opacity(
                        opacity: _fadeAnimation.value,
                        child: child,
                      ),
                    );
                  },
                  child: BeforeAfterSlider(
                    beforeImage: selfieImage!,
                    afterImage: resultImage!,
                    sliderPosition: _sliderPosition,
                    showFingerPrompt: !_hasUserInteracted,
                    onSliderChanged: (value) {
                      HapticFeedback.selectionClick();
                      setState(() {
                        _sliderPosition = value;
                        if (!_hasUserInteracted) {
                          _hasUserInteracted = true;
                        }
                      });
                    },
                  ),
                ),
              ),
            ),
          ),
        ),

        // Slide to compare hint - compact
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.touch_app,
                size: 12,
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
              ),
              const SizedBox(width: 6),
              Text(
                'SLIDE TO COMPARE',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.5,
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                ),
              ),
            ],
          ).animate().fadeIn(duration: 600.ms, delay: 300.ms),
        ),

        // Bottom action buttons - compact
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          decoration: BoxDecoration(
            color: colorScheme.surface,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 10,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _handleTryAgain,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    side: BorderSide(
                      color: colorScheme.outline.withValues(alpha: 0.3),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.replay,
                        size: 16,
                        color: colorScheme.secondary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'RETAKE',
                        style: TextStyle(
                          fontSize: 11,
                          letterSpacing: 1.5,
                          color: colorScheme.secondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Container(
                  height: 48,
                  decoration: BoxDecoration(
                    gradient: _isResultSaved
                        ? null
                        : LinearGradient(
                            colors: [
                              colorScheme.secondary,
                              const Color(0xFF9a7d45),
                            ],
                          ),
                    color: _isResultSaved
                        ? colorScheme.onSurface.withValues(alpha: 0.12)
                        : null,
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: _isResultSaved
                        ? null
                        : [
                            BoxShadow(
                              color: colorScheme.secondary.withValues(alpha: 0.2),
                              blurRadius: 20,
                              offset: const Offset(0, 8),
                            ),
                          ],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: _isResultSaved ? null : _saveToGallery,
                      borderRadius: BorderRadius.circular(10),
                      child: Center(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              _isResultSaved ? Icons.check_circle : Icons.download,
                              size: 16,
                              color: _isResultSaved
                                  ? colorScheme.onSurface.withValues(alpha: 0.38)
                                  : Colors.white,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              _isResultSaved ? 'SAVED' : 'SAVE LOOK',
                              style: TextStyle(
                                fontSize: 11,
                                letterSpacing: 1.5,
                                fontWeight: FontWeight.w600,
                                color: _isResultSaved
                                    ? colorScheme.onSurface.withValues(alpha: 0.38)
                                    : Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ============================================================================
// BEFORE/AFTER SLIDER WIDGET
// ============================================================================

class BeforeAfterSlider extends StatelessWidget {
  final Uint8List beforeImage;
  final Uint8List afterImage;
  final double sliderPosition;
  final bool showFingerPrompt;
  final ValueChanged<double> onSliderChanged;

  const BeforeAfterSlider({
    super.key,
    required this.beforeImage,
    required this.afterImage,
    required this.sliderPosition,
    required this.showFingerPrompt,
    required this.onSliderChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return GestureDetector(
      onHorizontalDragUpdate: (details) {
        final RenderBox box = context.findRenderObject() as RenderBox;
        final double width = box.size.width;
        final double position =
            (details.localPosition.dx / width).clamp(0.0, 1.0);
        onSliderChanged(position);
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          // After image (right side - the result)
          Image.memory(
            afterImage,
            fit: BoxFit.contain,
            width: double.infinity,
            height: double.infinity,
          ),

          // Before image (left side - clipped)
          ClipRect(
            clipper: _BeforeAfterClipper(sliderPosition),
            child: Image.memory(
              beforeImage,
              fit: BoxFit.contain,
              width: double.infinity,
              height: double.infinity,
            ),
          ),

          // Before label
          Positioned(
            left: 20,
            top: 20,
            child: _buildLabel('ORIGINAL', colorScheme, isHighlighted: sliderPosition > 0.5),
          ),

          // After label
          Positioned(
            right: 20,
            top: 20,
            child: _buildLabel('RESULT', colorScheme, isHighlighted: sliderPosition <= 0.5),
          ),

          // Slider handle
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            bottom: 0,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final position = sliderPosition * constraints.maxWidth;
                return Stack(
                  children: [
                    // Vertical divider line
                    Positioned(
                      left: position - 1,
                      top: 0,
                      bottom: 0,
                      child: Container(
                        width: 2,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.8),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.3),
                              blurRadius: 15,
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Handle in the center
                    Positioned(
                      left: position - 20,
                      top: 0,
                      bottom: 0,
                      child: Center(
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.4),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.25),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Icon(
                            Icons.code,
                            color: Colors.white,
                            size: 18,
                          ),
                        ),
                      ),
                    ),

                    // Finger prompt overlay - animated sliding finger
                    if (showFingerPrompt)
                      Positioned(
                        left: position - 60,
                        bottom: 70,
                        child: _FingerPromptOverlay(
                          colorScheme: colorScheme,
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLabel(String text, ColorScheme colorScheme, {bool isHighlighted = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: isHighlighted
            ? colorScheme.secondary
            : const Color(0xFF5A5A5A),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.5,
        ),
      ),
    );
  }
}

class _BeforeAfterClipper extends CustomClipper<Rect> {
  final double position;

  _BeforeAfterClipper(this.position);

  @override
  Rect getClip(Size size) {
    return Rect.fromLTRB(0, 0, size.width * position, size.height);
  }

  @override
  bool shouldReclip(_BeforeAfterClipper oldClipper) {
    return oldClipper.position != position;
  }
}

// ============================================================================
// FINGER PROMPT OVERLAY WIDGET
// ============================================================================

class _FingerPromptOverlay extends StatelessWidget {
  final ColorScheme colorScheme;

  const _FingerPromptOverlay({required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Animated finger icon with slide hint
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Animated finger pointing left
              const Icon(
                Icons.swipe,
                color: Colors.white,
                size: 22,
              )
                  .animate(
                    onPlay: (controller) => controller.repeat(reverse: true),
                  )
                  .moveX(
                    begin: -8,
                    end: 8,
                    duration: 800.ms,
                    curve: Curves.easeInOut,
                  ),
              const SizedBox(width: 8),
              Text(
                'Slide to reveal',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.95),
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        )
            .animate()
            .fadeIn(duration: 400.ms, delay: 300.ms)
            .scale(
              begin: const Offset(0.9, 0.9),
              end: const Offset(1.0, 1.0),
              duration: 400.ms,
              delay: 300.ms,
              curve: Curves.easeOut,
            ),
      ],
    );
  }
}
