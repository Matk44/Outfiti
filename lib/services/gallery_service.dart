import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:photo_manager/photo_manager.dart';

/// Service for fetching images from the Outfiti album in the device gallery.
///
/// This service provides read-only access to images saved by the app.
/// It handles:
/// - Permission requests for photo library access
/// - Album filtering to only read from 'Outfiti' album
/// - Sorting by most recent first
/// - Limiting results to 100 images
///
/// Platform differences handled:
/// - iOS: Uses PHAssetCollection to find albums by name
/// - Android: Uses folder path matching (Pictures/Outfiti or DCIM/Outfiti)
class GalleryService {
  /// The album name where app-generated images are saved
  static const String albumName = 'Outfiti';

  /// Maximum number of images to fetch
  /// Using 100 is safe due to lazy-loading in GridView.builder
  /// and on-demand thumbnail loading
  static const int maxImages = 100;

  /// Permission state cache
  PermissionState? _permissionState;

  /// Check and request photo library permission
  /// Returns true if permission is granted
  Future<bool> requestPermission() async {
    // Request read-only access to photo library
    final state = await PhotoManager.requestPermissionExtend(
      requestOption: const PermissionRequestOption(
        androidPermission: AndroidPermission(
          type: RequestType.image,
          mediaLocation: false, // We don't need location data
        ),
        iosAccessLevel: IosAccessLevel.readWrite, // Need readWrite for album access
      ),
    );

    _permissionState = state;
    return state.isAuth;
  }

  /// Check current permission state without requesting
  Future<PermissionState> checkPermission() async {
    _permissionState = await PhotoManager.requestPermissionExtend();
    return _permissionState!;
  }

  /// Get the current permission state
  PermissionState? get permissionState => _permissionState;

  /// Whether permission is currently granted
  bool get hasPermission => _permissionState?.isAuth ?? false;

  /// Whether permission was denied (user explicitly denied)
  bool get isDenied => _permissionState == PermissionState.denied;

  /// Whether permission is limited (iOS 14+ partial access)
  bool get isLimited => _permissionState == PermissionState.limited;

  /// Find the Outfiti album
  ///
  /// On iOS: Searches for album by exact name match
  /// On Android: Searches for folder containing 'Outfiti' in path
  Future<AssetPathEntity?> _findOutfitiAlbum() async {
    try {
      // Get all albums that contain images
      final List<AssetPathEntity> albums = await PhotoManager.getAssetPathList(
        type: RequestType.image,
        hasAll: false, // Don't include "All Photos" album
      );

      if (albums.isEmpty) {
        debugPrint('GalleryService: No albums found');
        return null;
      }

      // Find the Outfiti album
      // iOS: Album name matches exactly
      // Android: Folder name matches (path contains album name)
      for (final album in albums) {
        debugPrint('GalleryService: Checking album: ${album.name}');

        if (Platform.isIOS) {
          // iOS uses album name directly
          if (album.name == albumName) {
            debugPrint('GalleryService: Found iOS album: ${album.name}');
            return album;
          }
        } else if (Platform.isAndroid) {
          // Android uses folder path - check if name contains our album name
          // The album name might be just "Outfiti" or a full path like "Pictures/Outfiti"
          if (album.name == albumName ||
              album.name.endsWith('/$albumName') ||
              album.name.contains(albumName)) {
            debugPrint('GalleryService: Found Android album: ${album.name}');
            return album;
          }
        }
      }

      debugPrint('GalleryService: Outfiti album not found among ${albums.length} albums');
      return null;
    } catch (e) {
      debugPrint('GalleryService: Error finding album: $e');
      return null;
    }
  }

  /// Fetch recent images from the Outfiti album
  ///
  /// Returns a list of AssetEntity objects representing the images.
  /// The list is sorted by creation date (most recent first).
  /// Maximum of [maxImages] (100) images are returned.
  ///
  /// Returns empty list if:
  /// - Permission not granted
  /// - Album doesn't exist
  /// - No images in album
  Future<List<AssetEntity>> fetchRecentImages() async {
    // Check permission first
    if (!hasPermission) {
      final granted = await requestPermission();
      if (!granted) {
        debugPrint('GalleryService: Permission not granted');
        return [];
      }
    }

    // Find the Outfiti album
    final album = await _findOutfitiAlbum();
    if (album == null) {
      debugPrint('GalleryService: Album not found, returning empty list');
      return [];
    }

    // Get the count of assets in the album
    final int assetCount = await album.assetCountAsync;
    if (assetCount == 0) {
      debugPrint('GalleryService: Album is empty');
      return [];
    }

    debugPrint('GalleryService: Album has $assetCount images');

    // Fetch images, limited to maxImages, sorted by creation date (newest first)
    final List<AssetEntity> assets = await album.getAssetListPaged(
      page: 0,
      size: maxImages,
    );

    debugPrint('GalleryService: Fetched ${assets.length} images');
    return assets;
  }

  /// Get the thumbnail for an asset
  ///
  /// Returns thumbnail bytes suitable for grid display.
  /// Uses size 200x200 for optimal grid performance.
  Future<Uint8List?> getThumbnail(AssetEntity asset) async {
    return await asset.thumbnailDataWithSize(
      const ThumbnailSize(200, 200),
      quality: 80,
    );
  }

  /// Get the full-resolution image file
  ///
  /// Returns the original file for full-screen viewing.
  /// This may take longer than thumbnail loading.
  Future<File?> getFullImage(AssetEntity asset) async {
    return await asset.file;
  }

  /// Get the original bytes of an image for sharing
  Future<Uint8List?> getImageBytes(AssetEntity asset) async {
    return await asset.originBytes;
  }

  /// Open system settings to allow user to grant permission
  Future<void> openSettings() async {
    await PhotoManager.openSetting();
  }

  /// Clear cached data
  Future<void> clearCache() async {
    await PhotoManager.clearFileCache();
  }
}
