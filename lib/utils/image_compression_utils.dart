import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

/// Utility class for image compression and optimization
///
/// Provides consistent image compression across the app with smart quality
/// adjustment to maintain good results while keeping file sizes manageable.
class ImageCompressionUtils {
  // Maximum dimensions for different use cases
  static const int maxDimensionForAI = 1920; // Good quality for AI processing
  static const int maxDimensionForProfile = 1920; // Profile images

  // Quality settings (0-100)
  static const int highQuality = 90; // For very important images
  static const int goodQuality = 85; // Default - good balance

  /// Pick and compress image with standard settings
  ///
  /// This method:
  /// - Picks image from the specified source (gallery or camera)
  /// - Compresses to maxDimension while maintaining aspect ratio
  /// - Uses specified quality (defaults to 85 for good balance)
  /// - Returns compressed image bytes ready for upload
  ///
  /// The ImagePicker's built-in compression:
  /// - Maintains aspect ratio
  /// - Only resizes if image exceeds maxWidth/maxHeight
  /// - Applies JPEG compression at specified quality
  /// - Typically reduces 10-20MB images to 1-3MB while maintaining good quality
  static Future<Uint8List?> pickAndCompressImage({
    required ImageSource source,
    int maxDimension = maxDimensionForAI,
    int quality = goodQuality,
  }) async {
    final ImagePicker picker = ImagePicker();

    try {
      // Pick image with compression
      final XFile? image = await picker.pickImage(
        source: source,
        maxWidth: maxDimension.toDouble(),
        maxHeight: maxDimension.toDouble(),
        imageQuality: quality,
      );

      if (image == null) return null;

      // Get image bytes
      final Uint8List bytes = await image.readAsBytes();
      final int fileSize = bytes.length;

      debugPrint('Image compressed - Size: ${formatFileSize(fileSize)} (${(fileSize / 1024 / 1024).toStringAsFixed(2)} MB)');

      return bytes;
    } catch (e) {
      debugPrint('Error picking/compressing image: $e');
      rethrow;
    }
  }

  /// Get file size in megabytes
  static double getFileSizeMB(Uint8List bytes) {
    return bytes.length / 1024 / 1024;
  }

  /// Format file size for display
  static String formatFileSize(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    } else if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    } else {
      return '${(bytes / 1024 / 1024).toStringAsFixed(2)} MB';
    }
  }
}
