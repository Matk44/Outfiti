import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class OnboardingService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Checks if the current user has completed onboarding
  /// Returns true if onboardingCompleted is true, false otherwise
  ///
  /// NOTE: This method NO LONGER creates partial documents when the user doc
  /// doesn't exist. User documents should be created by:
  /// 1. App-side setupUserProfile() during sign-in
  /// 2. Server-side onUserCreated auth trigger (safety net)
  /// 3. Recovery check in main.dart (for existing broken users)
  Future<bool> hasCompletedOnboarding() async {
    final user = _auth.currentUser;
    if (user == null) return false;

    try {
      final docRef = _firestore.collection('users').doc(user.uid);
      final doc = await docRef.get();

      if (!doc.exists) {
        // Don't create a partial document here!
        // Let the auth flow handle document creation.
        // Just return false to trigger onboarding.
        return false;
      }

      final data = doc.data();
      if (data == null || !data.containsKey('onboardingCompleted')) {
        // Field doesn't exist yet - don't create partial update
        // Return false to show onboarding
        return false;
      }

      return data['onboardingCompleted'] == true;
    } catch (e) {
      // On error, assume onboarding not completed to be safe
      return false;
    }
  }

  /// Marks onboarding as completed for the current user
  /// If signedUp is true, also sets signedUpDuringOnboarding to true
  Future<void> completeOnboarding({bool signedUp = false}) async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      final data = {
        'onboardingCompleted': true,
        'onboardingCompletedAt': FieldValue.serverTimestamp(),
      };

      if (signedUp) {
        data['signedUpDuringOnboarding'] = true;
      }

      await _firestore.collection('users').doc(user.uid).set(
        data,
        SetOptions(merge: true),
      );
    } catch (e) {
      rethrow;
    }
  }

  /// Resets onboarding status (useful for testing)
  Future<void> resetOnboarding() async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      await _firestore.collection('users').doc(user.uid).update({
        'onboardingCompleted': false,
      });
    } catch (e) {
      rethrow;
    }
  }
}
