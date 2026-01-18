import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:vector_math/vector_math_64.dart' as vm;
import '../providers/theme_provider.dart';
import '../services/user_profile_service.dart';
import '../utils/image_compression_utils.dart';

/// Profile Image Picker Widget
///
/// Displays the user's profile image with an edit button overlay.
/// Allows users to pick a new image from gallery or camera.
/// Uploads the full original image (uncropped) for AI processing.
/// The circular display crops the image for visual purposes only.
/// Users can long-press to adjust the position/zoom of the image within the circle.
/// Uses profile.svg as placeholder when no image is set.
class ProfileImagePicker extends StatefulWidget {
  final String? currentImageUrl;
  final double size;
  final bool showEditButton;
  final Function(String)? onImageUploaded;
  final double initialScale;
  final double initialOffsetX;
  final double initialOffsetY;

  const ProfileImagePicker({
    super.key,
    this.currentImageUrl,
    this.size = 120,
    this.showEditButton = true,
    this.onImageUploaded,
    this.initialScale = 1.0,
    this.initialOffsetX = 0.0,
    this.initialOffsetY = 0.0,
  });

  @override
  State<ProfileImagePicker> createState() => _ProfileImagePickerState();
}

class _ProfileImagePickerState extends State<ProfileImagePicker> {
  final UserProfileService _profileService = UserProfileService();
  bool _isUploading = false;
  bool _isAdjustingPosition = false;

  // Transformation state
  late double _currentScale;
  late double _currentOffsetX;
  late double _currentOffsetY;
  final TransformationController _transformationController = TransformationController();

  @override
  void initState() {
    super.initState();
    _currentScale = widget.initialScale;
    _currentOffsetX = widget.initialOffsetX;
    _currentOffsetY = widget.initialOffsetY;
    _updateTransformationController();
  }

  @override
  void didUpdateWidget(ProfileImagePicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialScale != widget.initialScale ||
        oldWidget.initialOffsetX != widget.initialOffsetX ||
        oldWidget.initialOffsetY != widget.initialOffsetY) {
      _currentScale = widget.initialScale;
      _currentOffsetX = widget.initialOffsetX;
      _currentOffsetY = widget.initialOffsetY;
      _updateTransformationController();
    }
  }

  @override
  void dispose() {
    _transformationController.dispose();
    super.dispose();
  }

  void _updateTransformationController() {
    final matrix = Matrix4.identity();
    matrix.translateByVector3(vm.Vector3(_currentOffsetX, _currentOffsetY, 0.0));
    matrix.scaleByVector3(vm.Vector3(_currentScale, _currentScale, 1.0));
    _transformationController.value = matrix;
  }

  void _extractTransformation() {
    final matrix = _transformationController.value;
    _currentScale = matrix.getMaxScaleOnAxis();
    _currentOffsetX = matrix.getTranslation().x;
    _currentOffsetY = matrix.getTranslation().y;
  }

  Future<void> _saveTransformation() async {
    _extractTransformation();

    setState(() {
      _isAdjustingPosition = false;
    });

    try {
      await _profileService.updateProfileImageTransformation(
        scale: _currentScale,
        offsetX: _currentOffsetX,
        offsetY: _currentOffsetY,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Profile picture position saved'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving position: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
      debugPrint('Error saving transformation: $e');
    }
  }

  void _cancelAdjustment() {
    setState(() {
      _isAdjustingPosition = false;
      _currentScale = widget.initialScale;
      _currentOffsetX = widget.initialOffsetX;
      _currentOffsetY = widget.initialOffsetY;
      _updateTransformationController();
    });
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      // Use compression utility to pick and compress image
      final Uint8List? imageBytes = await ImageCompressionUtils.pickAndCompressImage(
        source: source,
        maxDimension: ImageCompressionUtils.maxDimensionForProfile,
        quality: ImageCompressionUtils.goodQuality,
      );

      if (imageBytes == null) return;

      // Show file size in debug
      debugPrint('Profile image selected: ${ImageCompressionUtils.formatFileSize(imageBytes.length)}');

      setState(() {
        _isUploading = true;
      });

      // Create temporary file from bytes for upload
      final tempDir = Directory.systemTemp;
      final tempFile = File('${tempDir.path}/profile_upload_${DateTime.now().millisecondsSinceEpoch}.jpg');
      await tempFile.writeAsBytes(imageBytes);

      try {
        // Upload the compressed image
        // The circular display will handle cropping for visual purposes only
        final downloadUrl = await _profileService.uploadProfileImage(tempFile);

        if (mounted) {
          setState(() {
            _isUploading = false;
            // Reset transformation for new image
            _currentScale = 1.0;
            _currentOffsetX = 0.0;
            _currentOffsetY = 0.0;
            _updateTransformationController();
          });
          widget.onImageUploaded?.call(downloadUrl);

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Profile picture updated successfully'),
                duration: Duration(seconds: 2),
              ),
            );
          }
        }
      } finally {
        // Clean up temp file
        try {
          if (await tempFile.exists()) {
            await tempFile.delete();
          }
        } catch (e) {
          debugPrint('Error deleting temp file: $e');
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isUploading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error uploading image: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
      debugPrint('Error picking/uploading image: $e');
    }
  }

  void _showImageSourceDialog() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        final themeProvider = Provider.of<ThemeProvider>(context);
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Choose Profile Picture',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 20),
              ListTile(
                leading: Icon(
                  Icons.photo_library,
                  color: themeProvider.accentColor,
                ),
                title: const Text('Choose from Gallery'),
                onTap: () {
                  Navigator.pop(context);
                  _pickImage(ImageSource.gallery);
                },
              ),
              ListTile(
                leading: Icon(
                  Icons.camera_alt,
                  color: themeProvider.accentColor,
                ),
                title: const Text('Take a Photo'),
                onTap: () {
                  Navigator.pop(context);
                  _pickImage(ImageSource.camera);
                },
              ),
              if (widget.currentImageUrl != null && widget.currentImageUrl!.isNotEmpty)
                ListTile(
                  leading: Icon(
                    Icons.control_camera,
                    color: themeProvider.accentColor,
                  ),
                  title: const Text('Adjust Position'),
                  onTap: () {
                    Navigator.pop(context);
                    setState(() {
                      _isAdjustingPosition = true;
                    });
                  },
                ),
              if (widget.currentImageUrl != null && widget.currentImageUrl!.isNotEmpty)
                ListTile(
                  leading: const Icon(
                    Icons.delete,
                    color: Colors.red,
                  ),
                  title: const Text('Remove Picture'),
                  onTap: () async {
                    final navigator = Navigator.of(context);
                    final messenger = ScaffoldMessenger.of(context);
                    navigator.pop();
                    try {
                      setState(() {
                        _isUploading = true;
                      });
                      await _profileService.deleteProfileImage();
                      if (!mounted) return;
                      setState(() {
                        _isUploading = false;
                        _currentScale = 1.0;
                        _currentOffsetX = 0.0;
                        _currentOffsetY = 0.0;
                        _updateTransformationController();
                      });
                      widget.onImageUploaded?.call('');
                      messenger.showSnackBar(
                        const SnackBar(
                          content: Text('Profile picture removed'),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    } catch (e) {
                      if (!mounted) return;
                      setState(() {
                        _isUploading = false;
                      });
                      messenger.showSnackBar(
                        SnackBar(
                          content: Text('Error removing image: $e'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, child) {
        final borderColor = themeProvider.isDarkTheme ? Colors.white : Colors.black;

        if (_isAdjustingPosition && widget.currentImageUrl != null && widget.currentImageUrl!.isNotEmpty) {
          return _buildAdjustmentMode(themeProvider, borderColor);
        }

        return GestureDetector(
          onTap: widget.showEditButton ? _showImageSourceDialog : null,
          onLongPress: (widget.currentImageUrl != null && widget.currentImageUrl!.isNotEmpty)
              ? () {
                  setState(() {
                    _isAdjustingPosition = true;
                  });
                }
              : null,
          child: _buildProfileCircle(themeProvider, borderColor),
        );
      },
    );
  }

  Widget _buildAdjustmentMode(ThemeProvider themeProvider, Color borderColor) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Instructions
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: themeProvider.accentColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: themeProvider.accentColor.withValues(alpha: 0.3),
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.info_outline,
                color: themeProvider.accentColor,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Pinch to zoom, drag to reposition',
                  style: TextStyle(
                    color: themeProvider.textPrimaryColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Interactive profile circle
        Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: themeProvider.accentColor,
              width: 3,
            ),
            boxShadow: [
              BoxShadow(
                color: themeProvider.accentColor.withValues(alpha: 0.3),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ClipOval(
            child: InteractiveViewer(
              transformationController: _transformationController,
              minScale: 0.5,
              maxScale: 4.0,
              boundaryMargin: const EdgeInsets.all(double.infinity),
              constrained: false,
              child: SizedBox(
                width: widget.size,
                height: widget.size,
                child: Image.network(
                  widget.currentImageUrl!,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) =>
                      _buildPlaceholder(themeProvider),
                ),
              ),
            ),
          ),
        ),

        const SizedBox(height: 24),

        // Action buttons
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            OutlinedButton.icon(
              onPressed: _cancelAdjustment,
              icon: const Icon(Icons.close, size: 18),
              label: const Text('Cancel'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                side: BorderSide(
                  color: themeProvider.textSecondaryColor.withValues(alpha: 0.3),
                ),
              ),
            ),
            const SizedBox(width: 16),
            FilledButton.icon(
              onPressed: _saveTransformation,
              icon: const Icon(Icons.check, size: 18),
              label: const Text('Save'),
              style: FilledButton.styleFrom(
                backgroundColor: themeProvider.accentColor,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildProfileCircle(ThemeProvider themeProvider, Color borderColor) {
    return Stack(
      children: [
        // Main avatar container
        Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: borderColor,
              width: 2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ClipOval(
            child: _isUploading
                ? Container(
                    color: Colors.grey.withValues(alpha: 0.1),
                    child: Center(
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        color: themeProvider.accentColor,
                      ),
                    ),
                  )
                : widget.currentImageUrl != null && widget.currentImageUrl!.isNotEmpty
                    ? _buildTransformedImage(themeProvider)
                    : _buildPlaceholder(themeProvider),
          ),
        ),
        // Edit button overlay
        if (widget.showEditButton && !_isUploading)
          Positioned(
            bottom: 0,
            right: 0,
            child: Container(
              width: widget.size * 0.3,
              height: widget.size * 0.3,
              decoration: BoxDecoration(
                color: themeProvider.accentColor,
                shape: BoxShape.circle,
                border: Border.all(
                  color: themeProvider.backgroundColor,
                  width: 2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Icon(
                Icons.camera_alt,
                color: themeProvider.isDarkTheme ? Colors.black : Colors.white,
                size: widget.size * 0.15,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildTransformedImage(ThemeProvider themeProvider) {
    final transformMatrix = Matrix4.identity();
    transformMatrix.translateByVector3(vm.Vector3(_currentOffsetX, _currentOffsetY, 0.0));
    transformMatrix.scaleByVector3(vm.Vector3(_currentScale, _currentScale, 1.0));

    return Transform(
      transform: transformMatrix,
      alignment: Alignment.center,
      child: Image.network(
        widget.currentImageUrl!,
        width: widget.size,
        height: widget.size,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) =>
            _buildPlaceholder(themeProvider),
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return Container(
            color: Colors.grey.withValues(alpha: 0.1),
            child: Center(
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: themeProvider.accentColor,
                value: loadingProgress.expectedTotalBytes != null
                    ? loadingProgress.cumulativeBytesLoaded /
                        loadingProgress.expectedTotalBytes!
                    : null,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildPlaceholder(ThemeProvider themeProvider) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: SvgPicture.asset(
        'assets/icons/profile.svg',
        width: widget.size,
        height: widget.size,
        fit: BoxFit.cover,
      ),
    );
  }
}
