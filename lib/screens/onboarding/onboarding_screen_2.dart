import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import '../../providers/theme_provider.dart';
import '../../services/user_profile_service.dart';
import 'onboarding_screen_3.dart';

/// Onboarding Screen 2 - Profile Setup
/// Users upload selfie, set display name, and choose theme
class OnboardingScreen2 extends StatefulWidget {
  const OnboardingScreen2({super.key});

  @override
  State<OnboardingScreen2> createState() => _OnboardingScreen2State();
}

class _OnboardingScreen2State extends State<OnboardingScreen2> {
  final UserProfileService _profileService = UserProfileService();
  final TextEditingController _nameController = TextEditingController();
  final ImagePicker _picker = ImagePicker();
  String _profileImageUrl = '';
  String? _selectedTheme;
  bool _isLoading = false;
  Uint8List? _userImage;

  @override
  void initState() {
    super.initState();
    _loadUserProfile();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _loadUserProfile() async {
    final profile = await _profileService.getUserProfile();
    if (profile != null && mounted) {
      setState(() {
        _nameController.text = profile['displayName'] ?? '';
        _profileImageUrl = profile['profileImageUrl'] ?? '';
        _selectedTheme = profile['selectedTheme'];
      });

      // Load image bytes if URL exists
      if (_profileImageUrl.isNotEmpty) {
        try {
          final response = await http.get(Uri.parse(_profileImageUrl));
          if (response.statusCode == 200) {
            if (mounted) {
              setState(() {
                _userImage = response.bodyBytes;
              });
            }
          }
        } catch (e) {
          debugPrint('Error loading profile image: $e');
        }
      }
    }
  }

  Future<void> _pickImage() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      );

      if (image != null) {
        final bytes = await image.readAsBytes();
        setState(() {
          _userImage = bytes;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error picking image: $e')),
        );
      }
    }
  }

  Future<void> _uploadProfileImage() async {
    if (_userImage == null) return;

    try {
      // Create a temporary file from the image bytes
      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/profile_temp.jpg');
      await file.writeAsBytes(_userImage!);

      // Upload the file using UserProfileService
      final downloadUrl = await _profileService.uploadProfileImage(file);

      setState(() {
        _profileImageUrl = downloadUrl;
      });

      debugPrint('Profile image uploaded successfully: $downloadUrl');
    } catch (e) {
      debugPrint('Error uploading profile image: $e');
      rethrow;
    }
  }

  Future<void> _saveProfileAndContinue() async {
    // Validate name
    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Please enter your name'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return;
    }

    // Validate photo
    if (_userImage == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Please upload a photo'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return;
    }

    // Validate theme selection
    if (_selectedTheme == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Please select a theme'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    // Get theme provider before async calls
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);

    try {
      // Upload profile image first
      await _uploadProfileImage();

      // Save display name
      await _profileService.updateDisplayName(_nameController.text.trim());

      // Save theme to Firestore
      await _profileService.updateTheme(_selectedTheme!);

      // Apply theme via provider
      themeProvider.setTheme(_selectedTheme!);

      if (mounted) {
        // Navigate to next screen
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => const OnboardingScreen3(),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving profile: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: themeProvider.backgroundColor,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 24),

              // Title
              Text(
                'We\'ll create your first look',
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: themeProvider.textPrimaryColor,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Text(
                'Upload your photo and let\'s try on a new outfit',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: themeProvider.textSecondaryColor,
                ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 12),

              // Profile Image Upload Frame
              _buildPreviewCard(theme.colorScheme),

              const SizedBox(height: 12),

              // Name Input
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Your Name',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: themeProvider.textSecondaryColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _nameController,
                    decoration: InputDecoration(
                      hintText: 'Enter your name',
                      hintStyle: TextStyle(
                        color: themeProvider.textSecondaryColor.withValues(alpha: 0.5),
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(
                          color: themeProvider.textSecondaryColor.withValues(alpha: 0.3),
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(
                          color: themeProvider.textSecondaryColor.withValues(alpha: 0.3),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(
                          color: themeProvider.accentColor,
                          width: 2,
                        ),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                    style: TextStyle(
                      color: themeProvider.textPrimaryColor,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // Theme Selection
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Choose Your App Theme',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: themeProvider.textSecondaryColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      initialValue: _selectedTheme,
                      decoration: InputDecoration(
                        hintText: 'Select a theme',
                        hintStyle: TextStyle(
                          color: themeProvider.textSecondaryColor.withValues(alpha: 0.5),
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(
                            color: themeProvider.textSecondaryColor.withValues(alpha: 0.3),
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(
                            color: themeProvider.textSecondaryColor.withValues(alpha: 0.3),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(
                            color: themeProvider.accentColor,
                            width: 2,
                          ),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      ),
                      dropdownColor: themeProvider.surfaceColor,
                      style: TextStyle(
                        color: themeProvider.textPrimaryColor,
                      ),
                      icon: Icon(
                        Icons.keyboard_arrow_down,
                        color: themeProvider.textPrimaryColor,
                      ),
                      items: themeProvider.availableThemes.map((themeName) {
                        final themeColors = _getThemePreviewColors(themeName);
                        return DropdownMenuItem<String>(
                          value: themeName,
                          child: Row(
                            children: [
                              // Color preview
                              Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: themeColors['background'],
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: themeProvider.textSecondaryColor.withValues(alpha: 0.2),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Container(
                                        decoration: BoxDecoration(
                                          color: themeColors['primary'],
                                          borderRadius: const BorderRadius.only(
                                            topLeft: Radius.circular(5),
                                            bottomLeft: Radius.circular(5),
                                          ),
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      child: Container(
                                        decoration: BoxDecoration(
                                          color: themeColors['accent'],
                                          borderRadius: const BorderRadius.only(
                                            topRight: Radius.circular(5),
                                            bottomRight: Radius.circular(5),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              Text(themeName),
                            ],
                          ),
                        );
                      }).toList(),
                      onChanged: (String? newTheme) async {
                        if (newTheme != null) {
                          setState(() {
                            _selectedTheme = newTheme;
                          });

                          // Apply theme immediately
                          final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
                          themeProvider.setTheme(newTheme);

                          // Save to Firestore
                          try {
                            await _profileService.updateTheme(newTheme);
                          } catch (e) {
                            debugPrint('Error saving theme: $e');
                          }
                        }
                      },
                    ),
                  ],
                ),

              const SizedBox(height: 16),

              // Continue Button
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _isLoading ? null : _saveProfileAndContinue,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(56),
                    backgroundColor: themeProvider.accentColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          'Continue',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: ThemeData.estimateBrightnessForColor(themeProvider.accentColor) ==
                                    Brightness.light
                                ? Colors.black
                                : Colors.white,
                          ),
                        ),
                ),
              ),

              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Map<String, Color> _getThemePreviewColors(String themeName) {
    switch (themeName) {
      case 'Divine Gold':
        return {
          'primary': const Color(0xFFFFFFFF),
          'accent': const Color(0xFFC5A059),
          'background': const Color(0xFFFFFCF9),
        };
      case 'Divine Vision':
        return {
          'primary': const Color(0xFFE8E4E1),
          'accent': const Color(0xFFD67649),
          'background': const Color(0xFFF5F3F0),
        };
      case 'Midnight Purple':
        return {
          'primary': const Color(0xFF2C1A47),
          'accent': const Color(0xFFFFD700),
          'background': const Color(0xFF1A1127),
        };
      case 'Forest Whisper':
        return {
          'primary': const Color(0xFF2C472C),
          'accent': const Color(0xFF98FB98),
          'background': const Color(0xFF1A271A),
        };
      case 'Sunset Glow':
        return {
          'primary': const Color(0xFF473C1A),
          'accent': const Color(0xFFFFA500),
          'background': const Color(0xFF272111),
        };
      case 'Twilight Rose':
        return {
          'primary': const Color(0xFF4A2C47),
          'accent': const Color(0xFFFF69B4),
          'background': const Color(0xFF271A25),
        };
      case 'Obsidian Night':
        return {
          'primary': const Color(0xFF1A1A1A),
          'accent': const Color(0xFFC5A059),
          'background': const Color(0xFF0F0F0F),
        };
      case 'Ocean Breeze':
        return {
          'primary': const Color(0xFF1A3C47),
          'accent': const Color(0xFF00CED1),
          'background': const Color(0xFF11272C),
        };
      case 'Ocean Pink':
        return {
          'primary': const Color(0xFFFDFBF5),
          'accent': const Color(0xFFFF69B4),
          'background': const Color(0xFFFAF8F0),
        };
      default:
        return {
          'primary': const Color(0xFFFFFFFF),
          'accent': const Color(0xFFC5A059),
          'background': const Color(0xFFFFFCF9),
        };
    }
  }

  Widget _buildPreviewCard(ColorScheme colorScheme) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: 280,
        ),
        child: AspectRatio(
          aspectRatio: 3 / 4,
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
                  ? Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.memory(
                          _userImage!,
                          fit: BoxFit.contain,
                          width: double.infinity,
                          height: double.infinity,
                        ),
                        // Change photo button
                        Positioned(
                          right: 12,
                          top: 12,
                          child: GestureDetector(
                            onTap: _pickImage,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 6),
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
                    )
                  : _buildImagePlaceholder(colorScheme),
            ),
          ),
        ),
      ),
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
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 8),
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
