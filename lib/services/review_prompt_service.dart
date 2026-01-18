import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:in_app_review/in_app_review.dart';
import 'credit_service.dart';

/// Service to manage app review prompts triggered at credit threshold
///
/// Behavior:
/// - Monitors credit changes via CreditService stream
/// - Triggers when credits drop to exactly 1
/// - Shows native review prompt once per user lifetime
/// - Displays on navigation away from result screen
class ReviewPromptService {
  static const String _reviewRequestedKey = 'review_requested';

  final CreditService _creditService;
  final InAppReview _inAppReview = InAppReview.instance;

  SharedPreferences? _prefs;
  bool _shouldShowReview = false;
  bool _isInitialized = false;
  int? _previousCredits;

  ReviewPromptService(this._creditService);

  /// Initialize service and start monitoring credits
  /// Must be called before using service (typically in main())
  Future<void> initialize() async {
    if (_isInitialized) return;

    _prefs = await SharedPreferences.getInstance();
    _isInitialized = true;

    debugPrint('ReviewPromptService: Initialized, starting credit monitoring');

    // Start listening to credit changes
    _creditService.creditsStream.listen(_onCreditsChanged);
  }

  /// Handle credit changes - detect transition to exactly 1
  void _onCreditsChanged(UserCredits credits) {
    final currentCredits = credits.credits;

    // Debug logging
    debugPrint(
        'ReviewPromptService: Credits changed from $_previousCredits to $currentCredits');

    // Check if credits just dropped to exactly 1
    // previousCredits must be > 1 to ensure we catch the transition
    if (_previousCredits != null &&
        _previousCredits! > 1 &&
        currentCredits == 1) {
      // Flag that review should be shown on next navigation
      _shouldShowReview = true;
      debugPrint(
          'ReviewPromptService: ✨ Credits hit 1! Review will be requested on next navigation');
    }

    _previousCredits = currentCredits;
  }

  /// Check if review has been shown before
  Future<bool> hasShownReview() async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs?.getBool(_reviewRequestedKey) ?? false;
  }

  /// Attempt to show review prompt
  /// Returns true if review was shown, false if conditions not met
  /// Call this in _onWillPop() of generation screens
  Future<bool> tryShowReview() async {
    debugPrint('ReviewPromptService: tryShowReview() called');

    // Check if already shown
    final alreadyShown = await hasShownReview();
    if (alreadyShown) {
      debugPrint(
          'ReviewPromptService: Review already shown previously, skipping');
      return false;
    }

    // Check if flag is set (credits hit 1)
    if (!_shouldShowReview) {
      debugPrint(
          'ReviewPromptService: Review flag not set (credits != 1 or no transition), skipping');
      return false;
    }

    // Check if review is available on this platform
    final available = await _inAppReview.isAvailable();
    if (!available) {
      debugPrint(
          'ReviewPromptService: In-app review not available on this platform');
      return false;
    }

    // Show the review prompt
    try {
      debugPrint('ReviewPromptService: 🎉 Showing review prompt!');
      await _inAppReview.requestReview();

      // Mark as shown in persistent storage
      await _prefs?.setBool(_reviewRequestedKey, true);
      _shouldShowReview = false;

      debugPrint(
          'ReviewPromptService: Review prompt shown successfully, marked as complete');
      return true;
    } catch (e) {
      debugPrint('ReviewPromptService: ❌ Error showing review: $e');
      return false;
    }
  }

  /// Reset review state for testing purposes
  /// Only works in debug mode for safety
  Future<void> resetForTesting() async {
    if (kDebugMode) {
      await _prefs?.remove(_reviewRequestedKey);
      _shouldShowReview = false;
      _previousCredits = null;
      debugPrint(
          'ReviewPromptService: 🔄 Reset for testing - review can be shown again');
    } else {
      debugPrint('ReviewPromptService: Reset only available in debug mode');
    }
  }
}
