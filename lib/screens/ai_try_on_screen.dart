import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:image_picker/image_picker.dart';
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

/// AI Try-On Screen - Upload photo and clothing items to virtually try on outfits
class AITryOnScreen extends StatefulWidget {
  const AITryOnScreen({super.key});

  @override
  State<AITryOnScreen> createState() => _AITryOnScreenState();
}

class _AITryOnScreenState extends State<AITryOnScreen>
    with SingleTickerProviderStateMixin {
  // State management
  Uint8List? _userImage;
  Uint8List? _resultImage;
  List<Uint8List?> _clothingItems = List.filled(6, null); // Up to 6 clothing items
  double _sliderPosition = 0.75; // Start at 3/4 to tease the reveal
  bool _isApplying = false;
  bool _hasUserInteracted = false; // Track if user has started sliding
  bool _isResultSaved = false; // Track if current result has been saved
  bool showResult = false; // Track if we should show result view
  bool _isLoadingProfileImage = false; // Track if loading profile image
  double _imageAspectRatio = 3 / 4; // Default aspect ratio (width/height)

  // Animation controller for reveal
  late AnimationController _revealController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;

  final ImagePicker _picker = ImagePicker();
  final OutfitStyleService _styleService = FirebaseOutfitStyleService();
  final CreditService _creditService = CreditService();
  final UserProfileService _profileService = UserProfileService();

  // Check if ready to apply: needs user photo + at least 1 clothing item
  bool get _canApply =>
      _userImage != null &&
      _clothingItems.any((item) => item != null);

  // Clothing categories with emoji and labels
  static const List<_ClothingCategory> _clothingCategories = [
    _ClothingCategory(emoji: '👕', label: 'Top'),
    _ClothingCategory(emoji: '👖', label: 'Bottom'),
    _ClothingCategory(emoji: '👟', label: 'Shoes'),
    _ClothingCategory(emoji: '🧥', label: 'Outerwear'),
    _ClothingCategory(emoji: '👜', label: 'Accessory'),
    _ClothingCategory(emoji: '✨', label: 'Outfit Ref'),
  ];

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
  }

  @override
  void dispose() {
    _revealController.dispose();
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

  Future<void> _pickImage() async {
    // Check if there's an unsaved result
    final canProceed = await _checkUnsavedResult('changing your photo');
    if (!canProceed) return;

    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      );

      if (image != null) {
        final bytes = await image.readAsBytes();
        final aspectRatio = await _calculateAspectRatio(bytes);
        setState(() {
          _userImage = bytes;
          _imageAspectRatio = aspectRatio;
          _resultImage = null; // Reset result when new image is picked
          _hasUserInteracted = false; // Reset interaction state
          _sliderPosition = 0.75; // Reset slider position
          _isResultSaved = false; // Reset saved state
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
  Future<void> _loadProfileImage(String profileImageUrl) async {
    // Haptic feedback
    HapticFeedback.lightImpact();

    setState(() {
      _isLoadingProfileImage = true;
    });

    try {
      final response = await http.get(Uri.parse(profileImageUrl));
      if (response.statusCode == 200) {
        final bytes = response.bodyBytes;
        final aspectRatio = await _calculateAspectRatio(bytes);
        if (mounted) {
          setState(() {
            _userImage = bytes;
            _imageAspectRatio = aspectRatio;
            _resultImage = null;
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

  // Pick a clothing item for the specified slot (0-5)
  Future<void> _pickClothingItem(int index) async {
    // Check if there's an unsaved result before changing clothing items
    final canProceed = await _checkUnsavedResult('changing clothing items');
    if (!canProceed) return;

    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      );

      if (image != null) {
        final bytes = await image.readAsBytes();
        HapticFeedback.lightImpact();
        setState(() {
          _clothingItems[index] = bytes;
          _resultImage = null; // Reset result when clothing changes
          _hasUserInteracted = false;
          _sliderPosition = 0.75;
          _isResultSaved = false;
        });
        _revealController.reset();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error picking clothing item: $e')),
        );
      }
    }
  }

  // Remove a clothing item from the specified slot
  void _removeClothingItem(int index) {
    HapticFeedback.lightImpact();
    setState(() {
      _clothingItems[index] = null;
      _resultImage = null;
      _hasUserInteracted = false;
      _sliderPosition = 0.75;
      _isResultSaved = false;
    });
    _revealController.reset();
  }

  Future<void> _applyTryOn() async {
    if (!_canApply) return;

    // Check credits BEFORE attempting try-on
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
      // Continue to try-on - server will handle if error occurred
    }

    setState(() {
      _isApplying = true;
    });

    try {
      // Filter out null clothing items
      final nonNullClothingItems = _clothingItems
          .where((item) => item != null)
          .cast<Uint8List>()
          .toList();

      // Call the AI try-on service with user image and clothing items
      final result = await _styleService.changeOutfitStyle(
        selfieImage: _userImage!,
        clothingItems: nonNullClothingItems,
      );

      if (mounted) {
        setState(() {
          _resultImage = result;
          showResult = true;
          _isApplying = false;
          _hasUserInteracted = false;
          _sliderPosition = 0.75;
          _isResultSaved = false;
        });

        // Trigger reveal animation
        _revealController.forward();
      }
    } on InsufficientCreditsException catch (e) {
      if (mounted) {
        setState(() {
          _isApplying = false;
        });
        _showInsufficientCreditsDialog(e.currentCredits);
      }
    } on RateLimitCooldownException {
      if (mounted) {
        setState(() {
          _isApplying = false;
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
      if (mounted) {
        setState(() {
          _isApplying = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Processing in progress. Please wait...'),
            backgroundColor: Theme.of(context).colorScheme.secondary,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } on OutfitStyleChangeException catch (e) {
      if (mounted) {
        setState(() {
          _isApplying = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Try-on failed: ${e.message}'),
            backgroundColor: Theme.of(context).colorScheme.error,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isApplying = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  // Save result image to gallery
  Future<void> _saveToGallery() async {
    if (_resultImage == null) return;

    try {
      // Save image to HairTryOn album for easy gallery retrieval
      await Gal.putImageBytes(_resultImage!, album: 'Outfiti');

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
    if (_resultImage == null) return;

    try {
      // Create a temporary file from the result image bytes
      final tempDir = await Directory.systemTemp.createTemp('outfiti_');
      final file = File('${tempDir.path}/outfit_style_result.jpg');
      await file.writeAsBytes(_resultImage!);

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
    // Block navigation during try-on - user would lose their credit
    if (_isApplying) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Please wait for try-on to complete. Leaving now will waste your credit.',
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
    if (_resultImage == null || _isResultSaved) {
      return true;
    }

    // Show confirmation dialog
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Unsaved Result'),
        content: const Text(
          'You have an unsaved try-on result. Would you like to save it before leaving?',
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

  // Check before changing photo or clothing items with unsaved result
  Future<bool> _checkUnsavedResult(String action) async {
    if (_resultImage != null && !_isResultSaved) {
      final shouldProceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Unsaved Result'),
          content: Text(
            'You have an unsaved try-on result. Would you like to save it before $action?',
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

      return shouldProceed ?? false;
    }
    return true;
  }

  // Handle try again button - check for unsaved result first
  Future<void> _handleTryAgain() async {
    if (_resultImage != null && !_isResultSaved) {
      final shouldProceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Unsaved Result'),
          content: const Text(
            'You have an unsaved try-on result. Would you like to save it before trying again?',
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
      _resultImage = null;
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
      child: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: Scaffold(
          backgroundColor: colorScheme.surface,
          body: SafeArea(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 400),
              child: showResult && _resultImage != null
                  ? _buildResultView(theme, colorScheme)
                  : _buildUploadView(theme, colorScheme),
            ),
          ),
        ),
      ),
    );
  }

  // Upload view with preview and clothing selector
  Widget _buildUploadView(ThemeData theme, ColorScheme colorScheme) {
    return Padding(
      key: const ValueKey('upload'),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          const SizedBox(height: 12),

          // Main Preview Card
          Expanded(
            child: Center(
              child: _buildPreviewCard(colorScheme),
            ),
          ),

          const SizedBox(height: 16),

          // Clothing Upload Section with inline Try It On button
          _buildClothingUploadSection(theme, colorScheme),

          const SizedBox(height: 16),
        ],
      ),
    );
  }

  // Result view with before/after slider
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
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: colorScheme.secondary.withValues(alpha: 0.15),
                    blurRadius: 40,
                    offset: const Offset(0, 10),
                  ),
                ],
                border: Border.all(
                  color: colorScheme.outline.withValues(alpha: 0.2),
                  width: 1,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
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
                    beforeImage: _userImage!,
                    afterImage: _resultImage!,
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
                        'TRY AGAIN',
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
                child: FilledButton(
                  onPressed: _isResultSaved ? null : _saveToGallery,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    backgroundColor: _isResultSaved ? null : colorScheme.secondary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        _isResultSaved ? Icons.check_circle : Icons.save_alt,
                        size: 16,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _isResultSaved ? 'SAVED' : 'SAVE LOOK',
                        style: const TextStyle(
                          fontSize: 11,
                          letterSpacing: 1.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildClothingUploadSection(ThemeData theme, ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section title with Try It On button
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Add Clothing Items',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurface,
              ),
            ),
            // Compact Try It On button
            _buildTryItOnButton(colorScheme),
          ],
        ),
        const SizedBox(height: 6),

        // Helper text
        Text(
          'Upload one item or several — we\'ll style them together.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 12),

        // Horizontal scrollable row of clothing upload slots
        SizedBox(
          height: 88,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: 6,
            separatorBuilder: (context, index) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final hasImage = _clothingItems[index] != null;
              final category = _clothingCategories[index];
              return _ClothingSlot(
                category: category,
                imageBytes: _clothingItems[index],
                onTap: () => _pickClothingItem(index),
                onRemove: hasImage ? () => _removeClothingItem(index) : null,
                colorScheme: colorScheme,
              );
            },
          ),
        ),
      ],
    ).animate().fadeIn(duration: 400.ms, delay: 200.ms).slideY(
          begin: 0.1,
          end: 0,
          duration: 400.ms,
          curve: Curves.easeOut,
        );
  }

  Widget _buildTryItOnButton(ColorScheme colorScheme) {
    return StreamBuilder<UserCredits>(
      stream: _creditService.creditsStream,
      builder: (context, snapshot) {
        final currentCredits = snapshot.data?.credits ?? 0;
        final hasCredits = currentCredits > 0;

        // Update button text based on credits
        final buttonText = hasCredits ? '✨ Try It On' : 'Credits';
        final buttonIcon = hasCredits ? null : Icons.add_circle_outline;

        return AnimatedOpacity(
          opacity: _canApply ? 1.0 : 0.4,
          duration: const Duration(milliseconds: 200),
          child: GestureDetector(
            onTap: _canApply && !_isApplying ? _applyTryOn : null,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: _canApply
                    ? colorScheme.secondary
                    : colorScheme.onSurface.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: _isApplying
                  ? SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: colorScheme.onSecondary,
                      ),
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (buttonIcon != null) ...[
                          Icon(
                            buttonIcon,
                            size: 14,
                            color: _canApply
                                ? colorScheme.onSecondary
                                : colorScheme.onSurface.withValues(alpha: 0.4),
                          ),
                          const SizedBox(width: 6),
                        ],
                        Text(
                          buttonText,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: _canApply
                                ? colorScheme.onSecondary
                                : colorScheme.onSurface.withValues(alpha: 0.4),
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        );
      },
    );
  }


  Widget _buildPreviewCard(ColorScheme colorScheme) {
    return AspectRatio(
      aspectRatio: _imageAspectRatio,
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: colorScheme.outline.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: _userImage != null
            ? _resultImage != null
                // Show slider with reveal animation when result is ready
                ? AnimatedBuilder(
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
                      beforeImage: _userImage!,
                      afterImage: _resultImage!,
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
                  )
                // Show just the user image (with loading overlay if applying)
                : _buildUserImagePreview(colorScheme)
            : _buildImagePlaceholder(colorScheme),
        ),
      ),
    ).animate().fadeIn(duration: 500.ms, delay: 100.ms).scale(
          begin: const Offset(0.98, 0.98),
          end: const Offset(1.0, 1.0),
          duration: 500.ms,
          curve: Curves.easeOut,
        );
  }

  Widget _buildUserImagePreview(ColorScheme colorScheme) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.memory(
          _userImage!,
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
        ),
        // Loading overlay when applying
        if (_isApplying)
          Container(
            color: Colors.black.withValues(alpha: 0.4),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(
                    color: colorScheme.secondary,
                    strokeWidth: 3,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Trying on outfit...',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      shadows: [
                        Shadow(
                          color: Colors.black.withValues(alpha: 0.5),
                          blurRadius: 4,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        // Tap to upload another photo hint
        if (!_isApplying)
          Positioned(
            right: 12,
            top: 12,
            child: GestureDetector(
              onTap: _pickImage,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.photo_camera_outlined,
                      size: 14,
                      color: Colors.white,
                    ),
                    SizedBox(width: 6),
                    Text(
                      'Change',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildImagePlaceholder(ColorScheme colorScheme) {
    return GestureDetector(
      onTap: _pickImage,
      child: Container(
        color: colorScheme.surfaceContainerHighest,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ClipOval(
              child: Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  color: colorScheme.secondary.withValues(alpha: 0.05),
                  shape: BoxShape.circle,
                ),
                child: Image.asset(
                  'assets/icons/reference_placeholder.png',
                  fit: BoxFit.cover,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Add Your Photo',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Upload a full-body photo for best results',
              style: TextStyle(
                fontSize: 14,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                border: Border.all(
                  color: colorScheme.secondary.withValues(alpha: 0.5),
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.upload,
                    size: 16,
                    color: colorScheme.secondary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Upload',
                    style: TextStyle(
                      fontSize: 14,
                      color: colorScheme.secondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            // Use Profile Photo toggle - minimal
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

                    return Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.account_circle,
                            size: 16,
                            color: colorScheme.secondary,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Use Profile Pic',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(width: 6),
                          if (_isLoadingProfileImage)
                            SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: colorScheme.secondary,
                              ),
                            )
                          else
                            Transform.scale(
                              scale: 0.8,
                              child: Switch(
                                value: _userImage != null,
                                onChanged: (value) {
                                  if (value && !_isLoadingProfileImage) {
                                    _loadProfileImage(profileImageUrl);
                                  }
                                },
                                activeTrackColor: colorScheme.secondary,
                                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }

}

// ============================================================================
// CLOTHING CATEGORY & SLOT WIDGET
// ============================================================================

class _ClothingCategory {
  final String emoji;
  final String label;

  const _ClothingCategory({
    required this.emoji,
    required this.label,
  });
}

class _ClothingSlot extends StatelessWidget {
  final _ClothingCategory category;
  final Uint8List? imageBytes;
  final VoidCallback onTap;
  final VoidCallback? onRemove;
  final ColorScheme colorScheme;

  const _ClothingSlot({
    required this.category,
    required this.imageBytes,
    required this.onTap,
    required this.onRemove,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    final hasImage = imageBytes != null;
    const size = 72.0;
    const borderRadius = 16.0;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedScale(
        scale: 1.0,
        duration: const Duration(milliseconds: 200),
        child: SizedBox(
          width: size,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Clothing upload slot
              Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(borderRadius),
                  border: Border.all(
                    color: hasImage
                        ? colorScheme.outline.withValues(alpha: 0.2)
                        : colorScheme.secondary.withValues(alpha: 0.3),
                    width: hasImage ? 1 : 2,
                  ),
                ),
                child: hasImage
                    ? Stack(
                        fit: StackFit.expand,
                        children: [
                          // Clothing image
                          ClipRRect(
                            borderRadius: BorderRadius.circular(borderRadius - 1),
                            child: Image.memory(
                              imageBytes!,
                              fit: BoxFit.cover,
                            ),
                          ),
                          // Remove button
                          if (onRemove != null)
                            Positioned(
                              top: 4,
                              right: 4,
                              child: GestureDetector(
                                onTap: onRemove,
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.6),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.close,
                                    size: 14,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      )
                    : Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(borderRadius - 1),
                          color: colorScheme.secondary.withValues(alpha: 0.05),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              category.emoji,
                              style: const TextStyle(fontSize: 28),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              category.label,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: colorScheme.secondary,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
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
          // After image (right side - the result, fills container)
          Image.memory(
            afterImage,
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
          ),

          // Before image (left side - clipped, shows full image)
          ClipRect(
            clipper: _BeforeAfterClipper(sliderPosition),
            child: Image.memory(
              beforeImage,
              fit: BoxFit.contain,
              width: double.infinity,
              height: double.infinity,
            ),
          ),

          // Before pill label
          Positioned(
            left: 12,
            top: 12,
            child: _buildLabel('ORIGINAL', colorScheme, isHighlighted: sliderPosition > 0.5),
          ),

          // After pill label
          Positioned(
            right: 12,
            top: 12,
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
                          color: Colors.white,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.3),
                              blurRadius: 4,
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Handle at the bottom
                    Positioned(
                      left: position - 18,
                      bottom: 20,
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: colorScheme.secondary,
                            width: 2.5,
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
                          Icons.swap_horiz,
                          color: colorScheme.secondary,
                          size: 18,
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

// ============================================================================
// SHARED DATA CLASSES AND WIDGETS (used by other screens)
// ============================================================================

/// Data class for outfit style/color information
class OutfitStyleData {
  final String name;
  final Color color;
  final String description;
  final String? imagePath;

  const OutfitStyleData({
    required this.name,
    required this.color,
    required this.description,
    this.imagePath,
  });
}

/// Widget for displaying outfit style options (used in describe and onboarding screens)
class OutfitStyleOption extends StatelessWidget {
  final OutfitStyleData data;
  final bool isSelected;
  final VoidCallback onTap;
  final bool compact;

  const OutfitStyleOption({
    super.key,
    required this.data,
    required this.isSelected,
    required this.onTap,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final size = compact ? 56.0 : 72.0;
    final borderRadius = compact ? 12.0 : 16.0;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedScale(
        scale: isSelected ? 1.0 : 0.95,
        duration: const Duration(milliseconds: 200),
        child: SizedBox(
          width: size,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(borderRadius),
                  border: isSelected
                      ? Border.all(
                          color: colorScheme.secondary,
                          width: compact ? 2 : 3,
                        )
                      : null,
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: colorScheme.secondary.withValues(alpha: 0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                child: Padding(
                  padding: EdgeInsets.all(isSelected ? (compact ? 2 : 4) : 0),
                  child: data.imagePath != null
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(isSelected ? (borderRadius - 4) : borderRadius),
                          child: Image.asset(
                            data.imagePath!,
                            fit: BoxFit.cover,
                          ),
                        )
                      : ClipRRect(
                          borderRadius: BorderRadius.circular(isSelected ? (borderRadius - 4) : borderRadius),
                          child: SvgPicture.asset(
                            'assets/icons/hair_sample.svg',
                            colorFilter: ColorFilter.mode(
                              data.color,
                              BlendMode.srcIn,
                            ),
                          ),
                        ),
                ),
              ),
              SizedBox(height: compact ? 4 : 6),
              SizedBox(
                height: compact ? 22 : 26,
                child: Text(
                  data.name,
                  style: TextStyle(
                    fontSize: compact ? 9 : 10,
                    height: 1.2,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                    color: isSelected
                        ? colorScheme.secondary
                        : colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

