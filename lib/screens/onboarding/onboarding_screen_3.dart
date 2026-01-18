import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import '../../services/user_profile_service.dart';
import '../ai_try_on_screen.dart'; // Import for OutfitStyleData and widgets
import 'onboarding_screen_4.dart';

/// Onboarding Screen 3 - Interactive outfit generation demo
/// Users get a guided taste of the describe feature during onboarding
/// Uses FREE onboarding generation (no credits consumed)
class OnboardingScreen3 extends StatefulWidget {
  const OnboardingScreen3({super.key});

  @override
  State<OnboardingScreen3> createState() => _OnboardingScreen3State();
}

class _OnboardingScreen3State extends State<OnboardingScreen3> {
  // State management
  Uint8List? _userImage;
  OutfitStyleData? _selectedStyleData;
  String _description = '';
  bool _isLoadingProfileImage = false; // Track if loading profile image
  double _imageAspectRatio = 3 / 4; // Default aspect ratio (width/height)

  // Custom style state
  bool _isCustomStyleSelected = false;
  String _customStyleDescription = '';

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
  final UserProfileService _profileService = UserProfileService();
  final TextEditingController _descriptionController = TextEditingController();
  final FocusNode _descriptionFocusNode = FocusNode();

  // Outfit style options - same as describe_screen.dart
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

  bool get _canGenerate => _userImage != null && _description.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();

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
            _placeholderIndex =
                (_placeholderIndex + 1) % _placeholderTexts.length;
          });
        }
      },
    );

    // Load profile image from Firebase
    _loadProfileImageFromFirebase();
  }

  @override
  void dispose() {
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

  // Load profile image from Firebase on init
  Future<void> _loadProfileImageFromFirebase() async {
    setState(() {
      _isLoadingProfileImage = true;
    });

    try {
      final profile = await _profileService.getUserProfile();
      final profileImageUrl = profile?['profileImageUrl'] ?? '';

      if (profileImageUrl.isNotEmpty) {
        final response = await http.get(Uri.parse(profileImageUrl));
        if (response.statusCode == 200 && mounted) {
          final bytes = response.bodyBytes;
          final aspectRatio = await _calculateAspectRatio(bytes);
          setState(() {
            _userImage = bytes;
            _imageAspectRatio = aspectRatio;
            _isLoadingProfileImage = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _isLoadingProfileImage = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingProfileImage = false;
        });
      }
    }
  }

  // Pick image and upload to Firebase as profile image
  Future<void> _pickImage() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      );

      if (image != null) {
        setState(() {
          _isLoadingProfileImage = true;
        });

        // Read bytes for display
        final bytes = await image.readAsBytes();
        final aspectRatio = await _calculateAspectRatio(bytes);

        // Upload to Firebase Storage
        final imageFile = File(image.path);
        await _profileService.uploadProfileImage(imageFile);

        if (mounted) {
          setState(() {
            _userImage = bytes;
            _imageAspectRatio = aspectRatio;
            _isLoadingProfileImage = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingProfileImage = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error uploading image: $e')),
        );
      }
    }
  }

  Future<void> _selectStyle(OutfitStyleData styleData) async {
    HapticFeedback.lightImpact();
    setState(() {
      _selectedStyleData = styleData;
      _isCustomStyleSelected = false; // Deselect custom when preset is selected
    });
  }

  // Show custom style input dialog
  Future<void> _showCustomStyleDialog() async {
    if (!mounted) return;

    final controller = TextEditingController(text: _customStyleDescription);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => _CustomStyleDialog(
        controller: controller,
        initialDescription: _customStyleDescription,
      ),
    );

    if (result != null && result.trim().isNotEmpty) {
      HapticFeedback.lightImpact();
      setState(() {
        _customStyleDescription = result.trim();
        _isCustomStyleSelected = true;
        _selectedStyleData = null; // Deselect preset when custom is used
      });
    }
  }

  void _generateOutfit() {
    if (!_canGenerate) return;

    // Determine which style description to use
    final targetStyle = _isCustomStyleSelected
        ? _customStyleDescription
        : (_selectedStyleData?.description ?? '');

    // Navigate to Screen 4 (processing screen) with parameters
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => OnboardingScreen4(
          userImage: _userImage!,
          description: _description.trim(),
          targetColor: targetStyle,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        backgroundColor: colorScheme.surface,
        body: SafeArea(
          child: _buildUploadView(theme, colorScheme),
        ),
      ),
    );
  }

  // Upload view with description input and style selector
  Widget _buildUploadView(ThemeData theme, ColorScheme colorScheme) {
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

          // Style Selector with inline Generate button
          _buildStyleSelectorWithAction(theme, colorScheme),

          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _buildDescriptionInput(ThemeData theme, ColorScheme colorScheme) {
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
                  : colorScheme.outline.withValues(alpha: 0.2),
              width: _descriptionFocusNode.hasFocus ? 2 : 1,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: TextField(
              controller: _descriptionController,
              focusNode: _descriptionFocusNode,
              maxLines: 2,
              maxLength: 500,
              decoration: InputDecoration(
                hintText: _placeholderTexts[_placeholderIndex],
                hintStyle: TextStyle(
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
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

  Widget _buildStyleSelectorWithAction(
      ThemeData theme, ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section title with Generate button
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
            itemCount: _outfitStyles.length + 1, // +1 for custom option
            separatorBuilder: (context, index) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              // First item is custom style option
              if (index == 0) {
                return _CustomStyleOption(
                  isSelected: _isCustomStyleSelected,
                  customDescription: _customStyleDescription,
                  onTap: _showCustomStyleDialog,
                  compact: false,
                );
              }

              // Rest are preset styles (offset by 1)
              final outfitStyle = _outfitStyles[index - 1];
              final isSelected =
                  _selectedStyleData == outfitStyle && !_isCustomStyleSelected;

              return OutfitStyleOption(
                data: outfitStyle,
                isSelected: isSelected,
                onTap: () => _selectStyle(outfitStyle),
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
    return AnimatedOpacity(
      opacity: _canGenerate ? 1.0 : 0.4,
      duration: const Duration(milliseconds: 200),
      child: GestureDetector(
        onTap: _canGenerate ? _generateOutfit : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: _canGenerate
                ? colorScheme.secondary
                : colorScheme.onSurface.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.auto_awesome,
                size: 14,
                color: _canGenerate
                    ? colorScheme.onSecondary
                    : colorScheme.onSurface.withValues(alpha: 0.4),
              ),
              const SizedBox(width: 6),
              Text(
                'Generate',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: _canGenerate
                      ? colorScheme.onSecondary
                      : colorScheme.onSurface.withValues(alpha: 0.4),
                ),
              ),
            ],
          ),
        ),
      ),
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
              ? _buildUserImagePreview(colorScheme)
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
          fit: BoxFit.contain,
          width: double.infinity,
          height: double.infinity,
        ),

        // Tap to upload another photo hint
        Positioned(
          right: 12,
          top: 12,
          child: GestureDetector(
            onTap: _pickImage,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
    // Show loading indicator while loading profile image
    if (_isLoadingProfileImage) {
      return Container(
        color: colorScheme.surfaceContainerHighest,
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
                'Loading your photo...',
                style: TextStyle(
                  fontSize: 14,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      );
    }

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
                      color: colorScheme.secondary.withValues(alpha: 0.05),
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// CUSTOM STYLE OPTION WIDGET
// ============================================================================

class _CustomStyleOption extends StatelessWidget {
  final bool isSelected;
  final String customDescription;
  final VoidCallback onTap;
  final bool compact;

  const _CustomStyleOption({
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
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Custom style circle with icon or edit
              Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(borderRadius),
                  border: Border.all(
                    color: isSelected
                        ? colorScheme.secondary
                        : colorScheme.outline.withValues(alpha: 0.3),
                    width: isSelected ? (compact ? 2 : 3) : 2,
                    strokeAlign: BorderSide.strokeAlignInside,
                  ),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color:
                                colorScheme.secondary.withValues(alpha: 0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      colorScheme.secondary.withValues(alpha: 0.15),
                      colorScheme.tertiary.withValues(alpha: 0.15),
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
                  isSelected && customDescription.isNotEmpty
                      ? 'My Style'
                      : 'Custom Style',
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

// ============================================================================
// CUSTOM STYLE DIALOG WIDGET
// ============================================================================

class _CustomStyleDialog extends StatefulWidget {
  final TextEditingController controller;
  final String initialDescription;

  const _CustomStyleDialog({
    required this.controller,
    required this.initialDescription,
  });

  @override
  State<_CustomStyleDialog> createState() => _CustomStyleDialogState();
}

class _CustomStyleDialogState extends State<_CustomStyleDialog> {
  late TextEditingController _controller;
  bool _isValid = false;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller;
    _isValid = _controller.text.trim().isNotEmpty;
    _controller.addListener(_onTextChanged);
  }

  void _onTextChanged() {
    final valid = _controller.text.trim().isNotEmpty;
    if (valid != _isValid) {
      setState(() {
        _isValid = valid;
      });
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Describe your desired outfit style in detail. Be specific about aesthetics, vibes, and influences.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            maxLines: 3,
            maxLength: 200,
            autofocus: true,
            decoration: InputDecoration(
              hintText:
                  'e.g., Y2K inspired with baggy jeans, vintage graphic tees, and retro sneakers',
              hintStyle: TextStyle(
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                fontSize: 13,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: colorScheme.outline.withValues(alpha: 0.3),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: colorScheme.secondary,
                  width: 2,
                ),
              ),
              contentPadding: const EdgeInsets.all(12),
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
              color: colorScheme.secondary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
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
                    style: theme.textTheme.bodySmall?.copyWith(
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
            style: TextStyle(color: colorScheme.onSurfaceVariant),
          ),
        ),
        FilledButton(
          onPressed: _isValid ? () => Navigator.pop(context, _controller.text) : null,
          style: FilledButton.styleFrom(
            backgroundColor: colorScheme.secondary,
          ),
          child: const Text('Apply'),
        ),
      ],
    );
  }
}
