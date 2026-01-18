import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:image_picker/image_picker.dart';
import 'package:gal/gal.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';

import '../providers/gallery_refresh_notifier.dart';
import '../services/outfit_service.dart';
import '../services/credit_service.dart';
import '../services/user_profile_service.dart';
import '../services/review_prompt_service.dart';
import '../widgets/paywall_modal.dart';
import '../widgets/credit_topup_modal.dart';
import 'ai_try_on_screen.dart'; // Import for OutfitStyleData and widgets

/// Describe screen - Users describe what they're dressing for
/// AI will generate outfit recommendations based on description and style direction
class DescribeScreen extends StatefulWidget {
  const DescribeScreen({super.key});

  @override
  State<DescribeScreen> createState() => _DescribeScreenState();
}

class _DescribeScreenState extends State<DescribeScreen>
    with SingleTickerProviderStateMixin {
  // State management
  Uint8List? _userImage;
  Uint8List? _resultImage;
  OutfitStyleData? _selectedStyleData;
  String _description = '';
  double _sliderPosition = 0.75; // Start at 3/4 to tease the reveal
  bool _isGenerating = false;
  bool _hasUserInteracted = false; // Track if user has started sliding
  bool _isResultSaved = false; // Track if current result has been saved
  bool showResult = false; // Track if we should show result view
  bool _isLoadingProfileImage = false; // Track if loading profile image
  double _imageAspectRatio = 3 / 4; // Default aspect ratio (width/height)

  // Custom color state
  bool _isCustomColorSelected = false;
  String _customColorDescription = '';

  // Animation controller for reveal
  late AnimationController _revealController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;

  // Rotating placeholder state
  int _placeholderIndex = 0;
  Timer? _placeholderTimer;

  static const List<String> _placeholderTexts = [
    'First date — want to look confident but relaxed',
    'I want to wear blue jeans but need the right top',
    'Going out tonight, casual but sharp',
    'Summer wedding, not too formal',
  ];

  final ImagePicker _picker = ImagePicker();
  final DescribeOutfitService _describeService =
  FirebaseDescribeOutfitService();
  final CreditService _creditService = CreditService();
  final UserProfileService _profileService = UserProfileService();
  final TextEditingController _descriptionController = TextEditingController();
  final FocusNode _descriptionFocusNode = FocusNode();

  // Outfit style options - organized by category
  static const List<OutfitStyleData> _outfitStyles = [
    // 🎯 BASELINE / EVERYDAY
    OutfitStyleData(
      name: 'Clean',
      color: Color(0xFFFFFFFF),
      description:
      'Clean, modern outfit with crisp silhouettes, neutral tones, minimal styling, and effortless polish.',
      imagePath: 'assets/icons/outfit_samples/clean.png',
    ),
    OutfitStyleData(
      name: 'Minimal',
      color: Color(0xFFE8E4DD),
      description:
      'Minimalist outfit with simple lines, restrained color palette, and uncluttered styling.',
      imagePath: 'assets/icons/outfit_samples/minimal.png',
    ),
    OutfitStyleData(
      name: 'Casual',
      color: Color(0xFFB8A898),
      description:
      'Relaxed everyday outfit that feels comfortable, easy, and natural without looking sloppy.',
      imagePath: 'assets/icons/outfit_samples/casual.png',
    ),
    OutfitStyleData(
      name: 'Elevated Casual',
      color: Color(0xFF9B8578),
      description:
      'Casual outfit with refined details, clean fit, and subtle polish — relaxed but intentional.',
      imagePath: 'assets/icons/outfit_samples/elevated_casual.png',
    ),
    OutfitStyleData(
      name: 'Classic',
      color: Color(0xFF6B5D52),
      description:
      'Timeless outfit with traditional silhouettes, balanced proportions, and enduring style choices.',
      imagePath: 'assets/icons/outfit_samples/classic.png',
    ),

    // 🧢 TREND / SUBCULTURE
    OutfitStyleData(
      name: 'Streetwear',
      color: Color(0xFF2D2D2D),
      description:
      'Contemporary streetwear outfit with relaxed proportions, layered pieces, and modern urban influence.',
      imagePath: 'assets/icons/outfit_samples/streetwear.png',
    ),
    OutfitStyleData(
      name: 'Y2K',
      color: Color(0xFFFF69B4),
      description:
      'Early-2000s inspired outfit with playful proportions, bold contrasts, and nostalgic styling.',
      imagePath: 'assets/icons/outfit_samples/y2k.png',
    ),
    OutfitStyleData(
      name: 'Indie',
      color: Color(0xFF7D6B5D),
      description:
      'Indie-inspired outfit with creative layering, thrifted energy, and expressive personal style.',
      imagePath: 'assets/icons/outfit_samples/indie.png',
    ),
    OutfitStyleData(
      name: 'Grunge',
      color: Color(0xFF3D3D3D),
      description:
      'Grunge-inspired outfit with darker tones, distressed textures, and rebellious attitude.',
      imagePath: 'assets/icons/outfit_samples/grunge.png',
    ),
    OutfitStyleData(
      name: 'Sporty',
      color: Color(0xFF5A8FAF),
      description:
      'Sport-inspired outfit with athletic elements, functional silhouettes, and casual energy.',
      imagePath: 'assets/icons/outfit_samples/sporty.png',
    ),

    // 🧥 POLISHED / FORMAL
    OutfitStyleData(
      name: 'Old Money',
      color: Color(0xFF8B7355),
      description:
      'Refined, understated outfit with tailored pieces, muted colors, and quiet luxury sensibility.',
      imagePath: 'assets/icons/outfit_samples/old_money.png',
    ),
    OutfitStyleData(
      name: 'Smart Casual',
      color: Color(0xFF5B6B7A),
      description:
      'Polished yet relaxed outfit suitable for semi-formal settings, balancing comfort and structure.',
      imagePath: 'assets/icons/outfit_samples/smart_casual.png',
    ),
    OutfitStyleData(
      name: 'Cocktail',
      color: Color(0xFF8B4789),
      description:
      'Stylish evening outfit appropriate for cocktail events, refined and elegant without being overly formal.',
      imagePath: 'assets/icons/outfit_samples/cocktail.png',
    ),
    OutfitStyleData(
      name: 'Formal',
      color: Color(0xFF1C1C1C),
      description:
      'Formal outfit with structured tailoring, elevated fabrics, and classic sophistication.',
      imagePath: 'assets/icons/outfit_samples/formal.png',
    ),
    OutfitStyleData(
      name: 'Business',
      color: Color(0xFF2B3E50),
      description:
      'Professional outfit suitable for work environments, clean, confident, and appropriate.',
      imagePath: 'assets/icons/outfit_samples/business.png',
    ),

    // 🌴 SEASONAL / DESTINATION
    OutfitStyleData(
      name: 'Coastal',
      color: Color(0xFF6FA8B8),
      description:
      'Relaxed coastal outfit with breathable fabrics, light colors, and effortless vacation energy.',
      imagePath: 'assets/icons/outfit_samples/coastal.png',
    ),
    OutfitStyleData(
      name: 'Beachwear',
      color: Color(0xFFFFA07A),
      description:
      'Beach-ready outfit with lightweight fabrics, relaxed silhouettes, and warm-weather practicality.',
      imagePath: 'assets/icons/outfit_samples/beachwear.png',
    ),
    OutfitStyleData(
      name: 'Resort',
      color: Color(0xFFFFD700),
      description:
      'Elevated vacation outfit designed for resorts, stylish yet relaxed with premium feel.',
      imagePath: 'assets/icons/outfit_samples/resort.png',
    ),
    OutfitStyleData(
      name: 'Summer Ready',
      color: Color(0xFFFFA500),
      description:
      'Warm-weather outfit optimized for heat, comfort, and breathability.',
      imagePath: 'assets/icons/outfit_samples/summer_ready.png',
    ),
    OutfitStyleData(
      name: 'Winter Layers',
      color: Color(0xFF4A5D6C),
      description:
      'Layered cold-weather outfit with warmth, texture, and functional styling.',
      imagePath: 'assets/icons/outfit_samples/winter_layers.png',
    ),
  ];

  bool get _canGenerate =>
      _userImage != null &&
          _description.trim().isNotEmpty;

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

    // Listen to text changes
    _descriptionController.addListener(() {
      setState(() {
        _description = _descriptionController.text;
      });
    });

    // Listen to focus changes to update border
    _descriptionFocusNode.addListener(() {
      setState(() {});
    });

    // Start rotating placeholder timer
    _placeholderTimer = Timer.periodic(
      const Duration(seconds: 4),
      (timer) {
        if (mounted && _descriptionController.text.isEmpty) {
          setState(() {
            _placeholderIndex = (_placeholderIndex + 1) % _placeholderTexts.length;
          });
        }
      },
    );
  }

  @override
  void dispose() {
    _revealController.dispose();
    _descriptionController.dispose();
    _descriptionFocusNode.dispose();
    _placeholderTimer?.cancel();
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

  Future<void> _selectColor(OutfitStyleData colorData) async {
    // Check if there's an unsaved result before changing color
    final canProceed =
    await _checkUnsavedResult('selecting a different color');
    if (!canProceed) return;

    HapticFeedback.lightImpact();
    setState(() {
      _selectedStyleData = colorData;
      _isCustomColorSelected =
      false; // Deselect custom when preset is selected
      _resultImage = null; // Reset result when color changes
      _hasUserInteracted = false; // Reset interaction state
      _sliderPosition = 0.75; // Reset slider position
      _isResultSaved = false; // Reset saved state
    });
    _revealController.reset();
  }

  // Show custom color input dialog
  Future<void> _showCustomColorDialog() async {
    // Check if there's an unsaved result before changing color
    final canProceed =
    await _checkUnsavedResult('creating a custom color');
    if (!canProceed || !mounted) return;

    final controller =
    TextEditingController(text: _customColorDescription);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => _CustomColorDialog(
        controller: controller,
        initialDescription: _customColorDescription,
      ),
    );

    if (result != null && result.trim().isNotEmpty) {
      HapticFeedback.lightImpact();
      setState(() {
        _customColorDescription = result.trim();
        _isCustomColorSelected = true;
        _selectedStyleData =
        null; // Deselect preset when custom is used
        _resultImage = null;
        _hasUserInteracted = false;
        _sliderPosition = 0.75;
        _isResultSaved = false;
      });
      _revealController.reset();
    }
  }

  Future<void> _generateHairstyle() async {
    if (!_canGenerate) return;

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
      _isGenerating = true;
    });

    // Determine which color description to use
    final targetColor = _isCustomColorSelected
        ? _customColorDescription
        : (_selectedStyleData?.description ?? '');

    // Get selected style name as vibes (if any)
    final selectedVibes = _isCustomColorSelected
        ? ''
        : (_selectedStyleData?.name ?? '');

    // TODO: Add contextTags from UI inputs
    final contextTags = '';

    try {
      final result = await _describeService.generateFromDescription(
        selfieImage: _userImage!,
        userDescription: _description.trim(),
        targetColor: targetColor,
        selectedVibes: selectedVibes,
        contextTags: contextTags,
        aspectRatio: _imageAspectRatio,
      );

      if (mounted) {
        setState(() {
          _resultImage = result;
          showResult = true;
          _isGenerating = false;
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
          _isGenerating = false;
        });
        _showInsufficientCreditsDialog(e.currentCredits);
      }
    } on RateLimitCooldownException {
      // Rate limited - show friendly message without exposing cooldown details
      if (mounted) {
        setState(() {
          _isGenerating = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
            const Text('Please wait a moment before trying again'),
            backgroundColor: Theme.of(context).colorScheme.secondary,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } on ConcurrentLimitException {
      // Too many concurrent requests
      if (mounted) {
        setState(() {
          _isGenerating = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
                'Processing in progress. Please wait...'),
            backgroundColor: Theme.of(context).colorScheme.secondary,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } on DescribeOutfitException catch (e) {
      if (mounted) {
        setState(() {
          _isGenerating = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Generation failed: ${e.message}'),
            backgroundColor: Theme.of(context).colorScheme.error,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isGenerating = false;
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
            content:
            const Text('Image saved to gallery successfully!'),
            backgroundColor:
            Theme.of(context).colorScheme.secondary,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save image: $e'),
            backgroundColor:
            Theme.of(context).colorScheme.error,
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
      final file = File('${tempDir.path}/outfit_result.jpg');
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
    // Block navigation during generation - user would lose their credit
    if (_isGenerating) {
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
    if (_resultImage == null || _isResultSaved) {
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

  // Check before changing photo or color with unsaved result
  Future<bool> _checkUnsavedResult(String action) async {
    if (_resultImage != null && !_isResultSaved) {
      final shouldProceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Unsaved Result'),
          content: Text(
            'You have an unsaved outfit result. Would you like to save it before $action?',
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
      onPopInvokedWithResult:
          (bool didPop, dynamic result) async {
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

  // Upload view with description input and color selector
  Widget _buildUploadView(
      ThemeData theme, ColorScheme colorScheme) {
    return Padding(
      key: const ValueKey('upload'),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          const SizedBox(height: 8),

          // Preview Card - takes available space
          Expanded(
            flex: 5,
            child: _buildPreviewCard(colorScheme),
          ),

          const SizedBox(height: 12),

          // Description Input - compact
          _buildDescriptionInput(theme, colorScheme),

          const SizedBox(height: 12),

          // Hair Color Selector with inline Generate button
          _buildColorSelectorWithAction(theme, colorScheme),

          const SizedBox(height: 12),
        ],
      ),
    );
  }

  // Result view with before/after slider
  Widget _buildResultView(
      ThemeData theme, ColorScheme colorScheme) {
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

  Widget _buildDescriptionInput(
      ThemeData theme, ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Label above text input
        Text(
          'Tell me what you\'re dressing for',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
            color: colorScheme.onSurface,
            fontSize: 13,
          ),
        ),
        const SizedBox(height: 4),
        // Helper text directly below title
        Text(
          'You can mention items you want to wear (jeans, sneakers, etc.)',
          style: theme.textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
            fontSize: 11,
          ),
        ),
        const SizedBox(height: 8),
        // Text input field
        Container(
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _descriptionFocusNode.hasFocus
                  ? colorScheme.secondary
                  : colorScheme.outline
                  .withValues(alpha: 0.2),
              width: _descriptionFocusNode.hasFocus ? 2 : 1,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: 12, vertical: 8),
            child: TextField(
              controller: _descriptionController,
              focusNode: _descriptionFocusNode,
              maxLines: 2,
              maxLength: 500,
              decoration: InputDecoration(
                hintText: _placeholderTexts[_placeholderIndex],
                hintStyle: TextStyle(
                  color: colorScheme.onSurfaceVariant
                      .withValues(alpha: 0.6),
                  fontSize: 13,
                ),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                errorBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
                counterStyle: TextStyle(
                  color: colorScheme.onSurfaceVariant,
                  fontSize: 10,
                ),
              ),
              style: TextStyle(
                color: colorScheme.onSurface,
                fontSize: 13,
              ),
            ),
          ),
        ),
      ],
    )
        .animate()
        .fadeIn(duration: 400.ms, delay: 100.ms)
        .slideY(
      begin: 0.1,
      end: 0,
      duration: 400.ms,
      curve: Curves.easeOut,
    );
  }

  Widget _buildColorSelectorWithAction(
      ThemeData theme, ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section title with Generate button
        Row(
          mainAxisAlignment:
          MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Style Direction (Optional)',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurface,
                fontSize: 13,
              ),
            ),
            // Compact Generate button
            _buildGenerateButton(colorScheme),
          ],
        ),
        const SizedBox(height: 8),

        // Horizontal scrollable row with custom option first
        SizedBox(
          height: 110,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount:
            _outfitStyles.length + 1, // +1 for custom option
            separatorBuilder: (context, index) =>
            const SizedBox(width: 10),
            itemBuilder: (context, index) {
              // First item is custom color option
              if (index == 0) {
                return _CustomColorOption(
                  isSelected: _isCustomColorSelected,
                  customDescription: _customColorDescription,
                  onTap: _showCustomColorDialog,
                  compact: false,
                );
              }

              // Rest are preset colors (offset by 1)
              final hairColor = _outfitStyles[index - 1];
              final isSelected = _selectedStyleData ==
                  hairColor &&
                  !_isCustomColorSelected;

              return OutfitStyleOption(
                data: hairColor,
                isSelected: isSelected,
                onTap: () => _selectColor(hairColor),
                compact: false,
              );
            },
          ),
        ),
      ],
    )
        .animate()
        .fadeIn(duration: 400.ms, delay: 200.ms)
        .slideY(
      begin: 0.1,
      end: 0,
      duration: 400.ms,
      curve: Curves.easeOut,
    );
  }

  Widget _buildGenerateButton(ColorScheme colorScheme) {
    return StreamBuilder<UserCredits>(
      stream: _creditService.creditsStream,
      builder: (context, snapshot) {
        final currentCredits = snapshot.data?.credits ?? 0;
        final hasCredits = currentCredits > 0;

        // Update button text based on credits
        final buttonText = hasCredits ? 'Generate' : 'Credits';
        final buttonIcon = hasCredits ? Icons.auto_awesome : Icons.add_circle_outline;

        return AnimatedOpacity(
          opacity: _canGenerate ? 1.0 : 0.4,
          duration: const Duration(milliseconds: 200),
          child: GestureDetector(
            onTap: _canGenerate && !_isGenerating ? _generateHairstyle : null,
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: _canGenerate
                    ? colorScheme.secondary
                    : colorScheme.onSurface
                    .withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: _isGenerating
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
                  Icon(
                    buttonIcon,
                    size: 14,
                    color: _canGenerate
                        ? colorScheme.onSecondary
                        : colorScheme.onSurface
                        .withValues(alpha: 0.4),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    buttonText,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
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
            color: colorScheme.outline
                .withValues(alpha: 0.2),
            width: 1,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: _userImage != null
            ? (_resultImage != null
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
            showFingerPrompt:
            !_hasUserInteracted,
            onSliderChanged: (value) {
              HapticFeedback
                  .selectionClick();
              setState(() {
                _sliderPosition = value;
                if (!_hasUserInteracted) {
                  _hasUserInteracted = true;
                }
              });
            },
          ),
        )
        // Show just the user image with loading overlay if generating
            : _buildUserImagePreview(
          colorScheme,
        ))
            : _buildImagePlaceholder(colorScheme),
        ),
      ),
    )
        .animate()
        .fadeIn(duration: 500.ms, delay: 100.ms)
        .scale(
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

        // Loading overlay when generating
        if (_isGenerating)
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
                    'Creating your outfit...',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      shadows: [
                        Shadow(
                          color: Colors.black
                              .withValues(alpha: 0.5),
                          blurRadius: 4,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

        // Tap to upload another photo hint if not generating
        if (!_isGenerating)
          Positioned(
            right: 12,
            top: 12,
            child: GestureDetector(
              onTap: _pickImage,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black
                      .withValues(alpha: 0.6),
                  borderRadius:
                  BorderRadius.circular(16),
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
        child: Center(
          child: SingleChildScrollView(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
            ClipOval(
              child: Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  color: colorScheme.secondary
                      .withValues(alpha: 0.05),
                  shape: BoxShape.circle,
                ),
                child: Image.asset(
                  'assets/icons/selfie_placeholder.png',
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
              'Full-body photos work best',
              style: TextStyle(
                fontSize: 14,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                border: Border.all(
                  color: colorScheme.secondary
                      .withValues(alpha: 0.5),
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
                final stream =
                _profileService.getUserProfileStream();
                if (stream == null) {
                  return const SizedBox.shrink();
                }

                return StreamBuilder<
                    DocumentSnapshot<Map<String, dynamic>>>(
                  stream: stream,
                  builder: (context, snapshot) {
                    final profileData =
                    snapshot.data?.data();
                    final profileImageUrl =
                        profileData?['profileImageUrl'] ?? '';

                    // Only show if profile image exists
                    if (profileImageUrl.isEmpty) {
                      return const SizedBox.shrink();
                    }

                    return Padding(
                      padding:
                      const EdgeInsets.only(top: 12),
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
                              color:
                              colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(width: 6),
                          if (_isLoadingProfileImage)
                            SizedBox(
                              width: 16,
                              height: 16,
                              child:
                              CircularProgressIndicator(
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
                                  if (!value) return;
                                  if (!_isLoadingProfileImage) {
                                    _loadProfileImage(
                                        profileImageUrl);
                                  }
                                },
                                activeTrackColor:
                                colorScheme.secondary,
                                materialTapTargetSize:
                                MaterialTapTargetSize
                                    .shrinkWrap,
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
        ),
      ),
    );
  }
}

// CUSTOM COLOR DIALOG WIDGET
class _CustomColorDialog extends StatefulWidget {
  final TextEditingController controller;
  final String initialDescription;

  const _CustomColorDialog({
    required this.controller,
    required this.initialDescription,
  });

  @override
  State<_CustomColorDialog> createState() =>
      _CustomColorDialogState();
}

class _CustomColorDialogState
    extends State<_CustomColorDialog> {
  late TextEditingController controller;
  bool isValid = false;

  @override
  void initState() {
    super.initState();
    controller = widget.controller;
    isValid = controller.text.trim().isNotEmpty;
    controller.addListener(onTextChanged);
  }

  void onTextChanged() {
    final valid = controller.text.trim().isNotEmpty;
    if (valid != isValid) {
      setState(() {
        isValid = valid;
      });
    }
  }

  @override
  void dispose() {
    controller.removeListener(onTextChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);

    return AlertDialog(
      title: Row(
        children: [
          Icon(
            Icons.style,
            color: colorScheme.secondary,
            size: 24,
          ),
          const SizedBox(width: 12),
          const Text('Custom Style'),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment:
        CrossAxisAlignment.start,
        children: [
          Text(
            'Describe your desired outfit style in detail. Be specific about aesthetics, vibes, and influences.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: controller,
            maxLines: 3,
            maxLength: 200,
            autofocus: true,
            decoration: InputDecoration(
              hintText:
              'e.g., Y2K inspired with baggy jeans, vintage graphic tees, and retro sneakers',
              hintStyle: TextStyle(
                color: colorScheme.onSurfaceVariant
                    .withValues(alpha: 0.6),
                fontSize: 13,
              ),
              border: OutlineInputBorder(
                borderRadius:
                BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: colorScheme.outline
                      .withValues(alpha: 0.3),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius:
                BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: colorScheme.secondary,
                  width: 2,
                ),
              ),
              contentPadding:
              const EdgeInsets.all(12),
            ),
            style: TextStyle(
              color: colorScheme.onSurface,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colorScheme.secondary
                  .withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              crossAxisAlignment:
              CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.lightbulb_outline,
                  size: 16,
                  color: colorScheme.secondary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Tip: Include details like specific brands, eras, or cultural influences for best results.',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(
                      color: colorScheme.secondary,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(
            'Cancel',
            style: TextStyle(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        FilledButton(
          onPressed: isValid
              ? () => Navigator.pop(
            context,
            controller.text,
          )
              : null,
          style: FilledButton.styleFrom(
            backgroundColor: colorScheme.secondary,
          ),
          child: const Text('Apply'),
        ),
      ],
    );
  }
}

// CUSTOM COLOR OPTION WIDGET
class _CustomColorOption extends StatelessWidget {
  final bool isSelected;
  final String customDescription;
  final VoidCallback onTap;
  final bool compact;

  const _CustomColorOption({
    required this.isSelected,
    required this.customDescription,
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
            mainAxisAlignment:
            MainAxisAlignment.center,
            children: [
              // Custom color circle with icon or edit
              Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  borderRadius:
                  BorderRadius.circular(borderRadius),
                  border: Border.all(
                    color: isSelected
                        ? colorScheme.secondary
                        : colorScheme.outline
                        .withValues(alpha: 0.3),
                    width: isSelected
                        ? (compact ? 2 : 3)
                        : 2,
                    strokeAlign:
                    BorderSide.strokeAlignInside,
                  ),
                  boxShadow: isSelected
                      ? [
                    BoxShadow(
                      color: colorScheme.secondary
                          .withValues(alpha: 0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                      : null,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      colorScheme.secondary
                          .withValues(alpha: 0.15),
                      colorScheme.tertiary
                          .withValues(alpha: 0.15),
                    ],
                  ),
                ),
                child: Center(
                  child: Icon(
                    isSelected ? Icons.edit : Icons.add,
                    size: compact ? 22 : 28,
                    color: isSelected
                        ? colorScheme.secondary
                        : colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              SizedBox(height: compact ? 4 : 6),
              // Label
              SizedBox(
                height: compact ? 22 : 26,
                child: Text(
                  isSelected &&
                      customDescription.isNotEmpty
                      ? 'My Style'
                      : 'Custom Style',
                  style: TextStyle(
                    fontSize: compact ? 9 : 10,
                    height: 1.2,
                    fontWeight: isSelected
                        ? FontWeight.w600
                        : FontWeight.w500,
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
