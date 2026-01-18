import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Service for managing user profile data in Firestore
class UserProfileService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Get current user's profile document
  DocumentReference<Map<String, dynamic>> get currentUserDoc {
    final userId = _auth.currentUser?.uid;
    if (userId == null) throw Exception('No user logged in');
    return _firestore.collection('users').doc(userId);
  }

  /// Initialize user profile with all required fields
  ///
  /// IMPORTANT: This method now accepts the User object directly to avoid
  /// a race condition where _auth.currentUser could be null immediately
  /// after signInWithCredential() returns.
  ///
  /// Uses set() with merge:true for idempotency - safe to call multiple times
  /// and won't overwrite existing fields like credits (set by Cloud Function).
  Future<void> initializeUserProfile(
    User user, {
    String? displayName,
    String? email,
    String? photoURL,
  }) async {
    try {
      // Use the passed user directly - don't re-fetch from _auth.currentUser
      // This fixes a race condition where currentUser could be null immediately after sign-in
      final userDoc = _firestore.collection('users').doc(user.uid);

      // Get device OS
      String os = 'unknown';
      try {
        if (Platform.isAndroid) {
          os = 'android';
        } else if (Platform.isIOS) {
          os = 'ios';
        }
      } catch (e) {
        debugPrint('Error detecting OS: $e');
      }

      // Use a Firestore transaction for atomic read-modify-write
      // This ensures:
      // - No race condition between checking existence and writing
      // - createdAt is only set once (first write wins)
      // - Won't overwrite fields set by auth trigger or Cloud Functions (like credits)
      // - Safe if called from multiple devices simultaneously
      await _firestore.runTransaction((transaction) async {
        final docSnapshot = await transaction.get(userDoc);

        final data = <String, dynamic>{
          'uid': user.uid,
          'email': email ?? user.email ?? '',
          'displayName': displayName ?? user.displayName ?? '',
          'profileImageUrl': photoURL ?? user.photoURL ?? '',
          'selectedTheme': 'Divine Gold',
          'os': os,
          'lastLoginTime': FieldValue.serverTimestamp(),
        };

        // Only set createdAt if document doesn't exist or field is missing
        if (!docSnapshot.exists || docSnapshot.data()?['createdAt'] == null) {
          data['createdAt'] = FieldValue.serverTimestamp();
        }

        // Use set with merge to avoid overwriting other fields (like credits)
        transaction.set(userDoc, data, SetOptions(merge: true));
      });

      debugPrint('User profile initialized/updated for ${user.uid}');
    } catch (e) {
      debugPrint('Error initializing user profile: $e');
      rethrow;
    }
  }

  /// Update user's display name
  Future<void> updateDisplayName(String displayName) async {
    try {
      await currentUserDoc.update({'displayName': displayName});
      await _auth.currentUser?.updateDisplayName(displayName);
      debugPrint('Display name updated to: $displayName');
    } catch (e) {
      debugPrint('Error updating display name: $e');
      rethrow;
    }
  }

  /// Update user's selected theme
  Future<void> updateTheme(String themeName) async {
    try {
      await currentUserDoc.update({'selectedTheme': themeName});
      debugPrint('Theme updated to: $themeName');
    } catch (e) {
      debugPrint('Error updating theme: $e');
      rethrow;
    }
  }

  /// Upload profile image and update profile
  Future<String> uploadProfileImage(File imageFile) async {
    try {
      final user = _auth.currentUser;
      if (user == null) throw Exception('No user logged in');

      debugPrint('Starting profile image upload for user: ${user.uid}');

      // Verify file exists and is readable
      if (!await imageFile.exists()) {
        throw Exception('Image file does not exist: ${imageFile.path}');
      }

      final fileSize = await imageFile.length();
      debugPrint('Image file size: ${fileSize} bytes');

      // Create a reference to the storage location
      final storageRef = _storage.ref().child('profile_images/${user.uid}/profile.jpg');
      debugPrint('Storage ref path: ${storageRef.fullPath}');
      debugPrint('Storage bucket: ${storageRef.bucket}');

      // Upload the file
      debugPrint('Starting file upload...');
      final uploadTask = await storageRef.putFile(imageFile);
      debugPrint('Upload completed. State: ${uploadTask.state}');

      // Get the download URL
      debugPrint('Getting download URL...');
      final downloadUrl = await uploadTask.ref.getDownloadURL();
      debugPrint('Download URL obtained: $downloadUrl');

      // Update Firestore with new image URL and reset transformation
      debugPrint('Updating Firestore...');
      await currentUserDoc.update({
        'profileImageUrl': downloadUrl,
        'profileImageScale': 1.0,
        'profileImageOffsetX': 0.0,
        'profileImageOffsetY': 0.0,
      });

      // Update Firebase Auth profile
      debugPrint('Updating Auth profile...');
      await user.updatePhotoURL(downloadUrl);

      debugPrint('Profile image uploaded successfully: $downloadUrl');
      return downloadUrl;
    } catch (e, stackTrace) {
      debugPrint('Error uploading profile image: $e');
      debugPrint('Stack trace: $stackTrace');
      rethrow;
    }
  }

  /// Get user profile data as a stream
  /// Returns null if no user is logged in
  Stream<DocumentSnapshot<Map<String, dynamic>>>? getUserProfileStream() {
    final userId = _auth.currentUser?.uid;
    if (userId == null) return null;
    return _firestore.collection('users').doc(userId).snapshots();
  }

  /// Get user profile data once
  Future<Map<String, dynamic>?> getUserProfile() async {
    try {
      final doc = await currentUserDoc.get();
      return doc.data();
    } catch (e) {
      debugPrint('Error getting user profile: $e');
      return null;
    }
  }

  /// Delete user profile image
  Future<void> deleteProfileImage() async {
    try {
      final user = _auth.currentUser;
      if (user == null) throw Exception('No user logged in');

      // Delete from storage
      try {
        final storageRef = _storage.ref().child('profile_images/${user.uid}/profile.jpg');
        await storageRef.delete();
      } catch (e) {
        debugPrint('Error deleting from storage (may not exist): $e');
      }

      // Update Firestore - clear image URL and transformation
      await currentUserDoc.update({
        'profileImageUrl': '',
        'profileImageScale': FieldValue.delete(),
        'profileImageOffsetX': FieldValue.delete(),
        'profileImageOffsetY': FieldValue.delete(),
      });

      // Update Firebase Auth profile
      await user.updatePhotoURL(null);

      debugPrint('Profile image deleted');
    } catch (e) {
      debugPrint('Error deleting profile image: $e');
      rethrow;
    }
  }

  /// Update profile image transformation (scale and offset for circular display)
  /// These parameters control how the image is displayed in the circular frame
  /// The original image URL remains unchanged for AI processing
  Future<void> updateProfileImageTransformation({
    required double scale,
    required double offsetX,
    required double offsetY,
  }) async {
    try {
      await currentUserDoc.update({
        'profileImageScale': scale,
        'profileImageOffsetX': offsetX,
        'profileImageOffsetY': offsetY,
      });
      debugPrint('Profile image transformation updated: scale=$scale, offset=($offsetX, $offsetY)');
    } catch (e) {
      debugPrint('Error updating profile image transformation: $e');
      rethrow;
    }
  }
}
