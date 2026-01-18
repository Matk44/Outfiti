import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/user_profile_service.dart';
import '../services/credit_service.dart';
import '../services/revenuecat_service.dart';

class AuthProvider with ChangeNotifier {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final UserProfileService _profileService = UserProfileService();
  final CreditService _creditService = CreditService();
  final RevenueCatService _revenueCatService = RevenueCatService();

  User? get currentUser => _auth.currentUser;
  User? get user => _auth.currentUser; // Alias for convenience
  bool get isAuthenticated => _auth.currentUser != null;

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  /// Setup user profile in Firestore with all required fields
  /// Also initializes credits for new users via Cloud Function
  /// And links RevenueCat subscriber to Firebase UID
  ///
  /// NOTE: This method now rethrows errors instead of silently swallowing them.
  /// Callers should handle errors appropriately (show user feedback, retry, etc.)
  Future<void> setupUserProfile(User user) async {
    try {
      // Initialize user profile document
      // Pass the user object directly to avoid race condition with currentUser
      await _profileService.initializeUserProfile(
        user,  // Pass user directly - fixes race condition
        displayName: user.displayName,
        email: user.email,
        photoURL: user.photoURL,
      );

      // Initialize RevenueCat and link to Firebase UID
      // This allows RevenueCat to track purchases by Firebase user
      try {
        await _revenueCatService.login(user.uid);
        debugPrint('RevenueCat logged in for user: ${user.uid}');
      } catch (e) {
        // Log but don't fail login if RevenueCat init fails
        debugPrint('Warning: RevenueCat login failed: $e');
      }

      // Initialize credits via Cloud Function
      // This is idempotent - safe to call on every login
      // Only sets up credits if they don't exist yet
      try {
        await _creditService.initializeCredits();
        debugPrint('Credits initialized for user: ${user.uid}');
      } catch (e) {
        // Log but don't fail login if credit init fails
        // The grantMonthlyCredits scheduled function can recover this
        debugPrint('Warning: Credit initialization failed: $e');
      }
    } catch (e) {
      debugPrint('Error setting up user profile: $e');
      // Rethrow so callers can handle the error (show user feedback, retry, etc.)
      // Previously this was silently swallowed, causing users to proceed without profiles
      rethrow;
    }
  }

  Future<void> signOut() async {
    // Logout from RevenueCat first
    try {
      await _revenueCatService.logout();
    } catch (e) {
      debugPrint('Warning: RevenueCat logout failed: $e');
    }

    await _auth.signOut();
    notifyListeners();
  }

  /// Deletes the currently authenticated user's Firebase Authentication account
  /// This will also automatically sign out the user
  Future<void> deleteAccount() async {
    final user = _auth.currentUser;

    if (user == null) {
      throw Exception('No user logged in');
    }

    // Logout from RevenueCat first
    try {
      await _revenueCatService.logout();
    } catch (e) {
      debugPrint('Warning: RevenueCat logout failed: $e');
    }

    // Delete the Firebase Authentication account
    // Note: This may fail if the user signed in too long ago
    // In that case, they need to re-authenticate first
    await user.delete();

    notifyListeners();
  }
}
