import 'package:flutter/foundation.dart';

/// A simple notifier that triggers gallery refresh when new images are saved.
///
/// This allows the GalleryScreen to update dynamically without requiring
/// an app restart. Any screen that saves an image should call [triggerRefresh]
/// after a successful save.
///
/// Usage:
/// ```dart
/// // After saving an image successfully:
/// context.read<GalleryRefreshNotifier>().triggerRefresh();
///
/// // In GalleryScreen, listen for changes:
/// context.watch<GalleryRefreshNotifier>().refreshCount;
/// ```
class GalleryRefreshNotifier extends ChangeNotifier {
  int _refreshCount = 0;

  /// A counter that increments each time a refresh is triggered.
  /// GalleryScreen can watch this to know when to reload images.
  int get refreshCount => _refreshCount;

  /// Call this after successfully saving an image to the gallery.
  /// This will notify all listeners (like GalleryScreen) to refresh.
  void triggerRefresh() {
    _refreshCount++;
    notifyListeners();
    debugPrint('GalleryRefreshNotifier: Refresh triggered (count: $_refreshCount)');
  }
}
