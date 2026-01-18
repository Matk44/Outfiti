import 'dart:io' as io;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:provider/provider.dart';
import '../providers/theme_provider.dart';

class ImageAdjustmentScreen extends StatefulWidget {
  final io.File imageFile;

  const ImageAdjustmentScreen({required this.imageFile, super.key});

  @override
  ImageAdjustmentScreenState createState() => ImageAdjustmentScreenState();
}

class ImageAdjustmentScreenState extends State<ImageAdjustmentScreen>
    with TickerProviderStateMixin {
  double _scale = 1.0;
  Offset _offset = Offset.zero;
  final double _minScale = 0.5;
  final double _maxScale = 4.0;
  final double _cropSize = 200.0;

  // Simplified gesture tracking
  double _baseScale = 1.0;
  Offset _baseOffset = Offset.zero;

  // Animation controllers for enhanced UI
  late AnimationController _pulseController;
  late AnimationController _checkButtonController;
  late Animation<double> _pulseAnimation;
  late Animation<double> _checkButtonScale;

  // State for check button
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();

    // Initialize animations
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    );

    _checkButtonController = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
    );

    _pulseAnimation = Tween<double>(
      begin: 1.0,
      end: 1.05,
    ).animate(CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOut,
    ));

    _checkButtonScale = Tween<double>(
      begin: 1.0,
      end: 0.9,
    ).animate(CurvedAnimation(
      parent: _checkButtonController,
      curve: Curves.easeInOut,
    ));

    // Start subtle pulse animation for crop circle
    _pulseController.repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _checkButtonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, child) {
        final accentColor = themeProvider.accentColor;
        final textPrimaryColor = themeProvider.textPrimaryColor;
        final isDark = themeProvider.isDarkTheme;

        return Scaffold(
          backgroundColor: themeProvider.backgroundColor,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            systemOverlayStyle: isDark
                ? SystemUiOverlayStyle.light
                : SystemUiOverlayStyle.dark,
            title: Text(
              'Adjust Image',
              style: TextStyle(
                fontFamily: 'Roboto',
                color: textPrimaryColor,
                fontWeight: FontWeight.w600,
                fontSize: 20,
              ),
            ),
            leading: IconButton(
              icon: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.close,
                  size: 20,
                  color: textPrimaryColor,
                ),
              ),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          body: Stack(
            children: [
              // Gradient background overlay
              Container(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment.center,
                    radius: 1.2,
                    colors: [
                      themeProvider.backgroundColor.withValues(alpha: 0.3),
                      themeProvider.backgroundColor.withValues(alpha: 0.8),
                      themeProvider.backgroundColor,
                    ],
                    stops: const [0.0, 0.6, 1.0],
                  ),
                ),
              ),

              // Instructions with enhanced styling
              Positioned(
                top: 80,
                left: 20,
                right: 20,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(25),
                    border: Border.all(
                      color: accentColor.withValues(alpha: 0.3),
                      width: 1,
                    ),
                  ),
                  child: Text(
                    'Pinch to zoom • Drag to move',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: textPrimaryColor.withValues(alpha: 0.9),
                      fontSize: 16,
                      fontFamily: 'Roboto',
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ),

              // Image area with enhanced gestures
              Center(
                child: SizedBox(
                  width: _cropSize * 2,
                  height: _cropSize * 2,
                  child: GestureDetector(
                    onScaleStart: (details) {
                      _baseScale = _scale;
                      _baseOffset = _offset;
                      HapticFeedback.selectionClick();
                    },
                    onScaleUpdate: (details) {
                      setState(() {
                        if (details.pointerCount == 1) {
                          // Pan with one finger
                          _offset += details.focalPointDelta;
                        } else {
                          // Scale with multiple fingers
                          double newScale = _baseScale * details.scale;
                          newScale = newScale.clamp(_minScale, _maxScale);

                          // Adjust offset to keep the point under the focal point fixed
                          Offset focalPoint = details.localFocalPoint;
                          _offset = focalPoint -
                              (focalPoint - _baseOffset) *
                                  (newScale / _baseScale);
                          _scale = newScale;
                        }

                        // Constrain the offset to prevent the image from moving too far
                        _offset = _constrainOffset(_offset, _scale);
                      });
                    },
                    child: Container(
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.fromBorderSide(
                            BorderSide(color: Colors.transparent)),
                      ),
                      child: Center(
                        child: SizedBox(
                          width: _cropSize,
                          height: _cropSize,
                          child: ClipOval(
                            child: Container(
                              color: themeProvider.surfaceColor,
                              child: Transform.translate(
                                offset: _offset,
                                child: Transform.scale(
                                  scale: _scale,
                                  child: Image.file(
                                    widget.imageFile,
                                    fit: BoxFit.cover,
                                    width: _cropSize,
                                    height: _cropSize,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              // Enhanced crop overlay with subtle animation
              Center(
                child: IgnorePointer(
                  child: AnimatedBuilder(
                    animation: _pulseAnimation,
                    builder: (context, child) {
                      return Transform.scale(
                        scale: _pulseAnimation.value,
                        child: Container(
                          width: _cropSize,
                          height: _cropSize,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: accentColor,
                              width: 2.5,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: accentColor.withValues(alpha: 0.3),
                                blurRadius: 15,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),

              // Corner guides for better visual hierarchy
              Center(
                child: IgnorePointer(
                  child: SizedBox(
                    width: _cropSize + 40,
                    height: _cropSize + 40,
                    child: Stack(
                      children: [
                        // Top-left corner
                        Positioned(
                          top: 0,
                          left: 0,
                          child: Container(
                            width: 20,
                            height: 20,
                            decoration: BoxDecoration(
                              border: Border(
                                top: BorderSide(
                                    color: accentColor.withValues(alpha: 0.4),
                                    width: 2),
                                left: BorderSide(
                                    color: accentColor.withValues(alpha: 0.4),
                                    width: 2),
                              ),
                            ),
                          ),
                        ),
                        // Top-right corner
                        Positioned(
                          top: 0,
                          right: 0,
                          child: Container(
                            width: 20,
                            height: 20,
                            decoration: BoxDecoration(
                              border: Border(
                                top: BorderSide(
                                    color: accentColor.withValues(alpha: 0.4),
                                    width: 2),
                                right: BorderSide(
                                    color: accentColor.withValues(alpha: 0.4),
                                    width: 2),
                              ),
                            ),
                          ),
                        ),
                        // Bottom-left corner
                        Positioned(
                          bottom: 0,
                          left: 0,
                          child: Container(
                            width: 20,
                            height: 20,
                            decoration: BoxDecoration(
                              border: Border(
                                bottom: BorderSide(
                                    color: accentColor.withValues(alpha: 0.4),
                                    width: 2),
                                left: BorderSide(
                                    color: accentColor.withValues(alpha: 0.4),
                                    width: 2),
                              ),
                            ),
                          ),
                        ),
                        // Bottom-right corner
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: Container(
                            width: 20,
                            height: 20,
                            decoration: BoxDecoration(
                              border: Border(
                                bottom: BorderSide(
                                    color: accentColor.withValues(alpha: 0.4),
                                    width: 2),
                                right: BorderSide(
                                    color: accentColor.withValues(alpha: 0.4),
                                    width: 2),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // Enhanced check button with accent color
              Positioned(
                bottom: 80,
                right: 20,
                child: AnimatedBuilder(
                  animation: _checkButtonScale,
                  builder: (context, child) {
                    return Transform.scale(
                      scale: _checkButtonScale.value,
                      child: GestureDetector(
                        onTapDown: (_) {
                          _checkButtonController.forward();
                          HapticFeedback.heavyImpact();
                        },
                        onTapUp: (_) {
                          _checkButtonController.reverse();
                        },
                        onTapCancel: () {
                          _checkButtonController.reverse();
                        },
                        onTap: _isProcessing
                            ? null
                            : () {
                                setState(() {
                                  _isProcessing = true;
                                });
                                _cropAndReturnImage();
                              },
                        child: Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            gradient: _isProcessing
                                ? LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                      Colors.grey.withValues(alpha: 0.6),
                                      Colors.grey.withValues(alpha: 0.8),
                                    ],
                                  )
                                : LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                      accentColor,
                                      accentColor.withValues(alpha: 0.8),
                                    ],
                                  ),
                            borderRadius: BorderRadius.circular(32),
                            boxShadow: _isProcessing
                                ? [
                                    BoxShadow(
                                      color: Colors.grey.withValues(alpha: 0.3),
                                      blurRadius: 15,
                                      spreadRadius: 1,
                                      offset: const Offset(0, 4),
                                    ),
                                  ]
                                : [
                                    BoxShadow(
                                      color: accentColor.withValues(alpha: 0.4),
                                      blurRadius: 20,
                                      spreadRadius: 2,
                                      offset: const Offset(0, 8),
                                    ),
                                  ],
                            border: Border.all(
                              color: isDark
                                  ? Colors.white.withValues(alpha: 0.2)
                                  : Colors.black.withValues(alpha: 0.1),
                              width: 1,
                            ),
                          ),
                          child: Center(
                            child: _isProcessing
                                ? SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(
                                      color: isDark ? Colors.black : Colors.white,
                                      strokeWidth: 2.5,
                                    ),
                                  )
                                : Icon(
                                    Icons.check,
                                    color: isDark ? Colors.black : Colors.white,
                                    size: 32,
                                  ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),

              // Scale indicator
              Positioned(
                bottom: 40,
                left: 20,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: accentColor.withValues(alpha: 0.3),
                      width: 1,
                    ),
                  ),
                  child: Text(
                    '${(_scale * 100).toInt()}%',
                    style: TextStyle(
                      color: textPrimaryColor.withValues(alpha: 0.8),
                      fontFamily: 'Roboto',
                      fontWeight: FontWeight.w500,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Offset _constrainOffset(Offset offset, double scale) {
    // Reasonable constraints based on scale
    final maxOffset = _cropSize * 0.6 * (_scale - 1).clamp(0.0, 1.0);
    return Offset(
      offset.dx.clamp(-maxOffset, maxOffset),
      offset.dy.clamp(-maxOffset, maxOffset),
    );
  }

  Future<void> _cropAndReturnImage() async {
    if (!mounted) return;

    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);

    try {
      // Enhanced loading dialog with modern design
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: themeProvider.surfaceColor,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: themeProvider.accentColor.withValues(alpha: 0.3),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.5),
                  blurRadius: 30,
                  spreadRadius: 10,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 60,
                  height: 60,
                  child: CircularProgressIndicator(
                    color: themeProvider.accentColor,
                    strokeWidth: 4,
                    backgroundColor: themeProvider.accentColor.withValues(alpha: 0.1),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Processing Image',
                  style: TextStyle(
                    color: themeProvider.textPrimaryColor,
                    fontFamily: 'Roboto',
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Creating your perfect crop...',
                  style: TextStyle(
                    color: themeProvider.textSecondaryColor,
                    fontFamily: 'Roboto',
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      final imageBytes = await widget.imageFile.readAsBytes();
      final originalImage = img.decodeImage(imageBytes);

      if (originalImage == null) {
        if (mounted) Navigator.pop(context);
        throw Exception('Failed to decode image');
      }

      // Get the actual displayed image dimensions within the circular crop area
      final screenCropSize = _cropSize;

      // Calculate how the image is scaled to fit the crop area initially
      final originalWidth = originalImage.width.toDouble();
      final originalHeight = originalImage.height.toDouble();
      final originalAspectRatio = originalWidth / originalHeight;

      // The image is displayed with BoxFit.cover, so we need to calculate
      // how it's actually scaled and positioned
      double baseScale;
      if (originalAspectRatio > 1.0) {
        // Landscape image - height fills the crop area
        baseScale = screenCropSize / originalHeight;
      } else {
        // Portrait or square image - width fills the crop area
        baseScale = screenCropSize / originalWidth;
      }

      // Total scale including user adjustments
      final totalScale = baseScale * _scale;

      // Calculate the size of the crop area in original image coordinates
      final cropSizeInOriginal = screenCropSize / totalScale;

      // Calculate the center point in original image coordinates
      final baseCenterX = originalWidth / 2;
      final baseCenterY = originalHeight / 2;

      // Apply user offset (inverted because moving the image right means cropping more from the left)
      final adjustedCenterX = baseCenterX - (_offset.dx / totalScale);
      final adjustedCenterY = baseCenterY - (_offset.dy / totalScale);

      // Calculate crop bounds ensuring they stay within image bounds
      final halfCropSize = cropSizeInOriginal / 2;
      final cropLeft =
          (adjustedCenterX - halfCropSize).clamp(0.0, originalWidth);
      final cropTop = (adjustedCenterY - halfCropSize).clamp(0.0, originalHeight);
      final cropRight =
          (adjustedCenterX + halfCropSize).clamp(0.0, originalWidth);
      final cropBottom =
          (adjustedCenterY + halfCropSize).clamp(0.0, originalHeight);

      final cropWidth = cropRight - cropLeft;
      final cropHeight = cropBottom - cropTop;

      if (cropWidth <= 0 || cropHeight <= 0) {
        if (mounted) Navigator.pop(context);
        throw Exception('Invalid crop dimensions');
      }

      // Perform the crop
      final croppedImage = img.copyCrop(
        originalImage,
        x: cropLeft.toInt(),
        y: cropTop.toInt(),
        width: cropWidth.toInt(),
        height: cropHeight.toInt(),
      );

      // Ensure the cropped image is square to prevent fisheye effect
      final minDimension =
          cropWidth < cropHeight ? cropWidth.toInt() : cropHeight.toInt();
      final squareCroppedImage = img.copyCrop(
        croppedImage,
        x: ((cropWidth - minDimension) / 2).toInt(),
        y: ((cropHeight - minDimension) / 2).toInt(),
        width: minDimension,
        height: minDimension,
      );

      // Resize to standard profile size maintaining aspect ratio
      final resizedImage = img.copyResize(
        squareCroppedImage,
        width: 1024,
        height: 1024,
        interpolation: img.Interpolation.cubic,
      );

      // Save to temporary file
      final tempDir = io.Directory.systemTemp;
      final tempFile = io.File(
          '${tempDir.path}/cropped_profile_${DateTime.now().millisecondsSinceEpoch}.jpg');

      await tempFile.writeAsBytes(img.encodeJpg(resizedImage, quality: 92));

      if (mounted) Navigator.pop(context); // Close loading dialog
      if (mounted) Navigator.pop(context, tempFile);
    } catch (e) {
      // Reset processing state on error
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });

        // Make sure to close loading dialog if it's open
        if (Navigator.canPop(context)) {
          Navigator.pop(context);
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error processing image: ${e.toString()}'),
            backgroundColor: Colors.red.withValues(alpha: 0.8),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    }
  }
}
