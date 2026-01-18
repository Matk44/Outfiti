import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Exception thrown when user doesn't have enough credits
class InsufficientCreditsException implements Exception {
  final int currentCredits;
  final int requiredCredits;

  InsufficientCreditsException({
    required this.currentCredits,
    required this.requiredCredits,
  });

  @override
  String toString() =>
      'Insufficient credits: have $currentCredits, need $requiredCredits';
}

/// User plan types - must match Cloud Functions
enum UserPlan {
  free,
  monthlyPro,
  annualPro;

  /// Convert to string for Cloud Function calls
  String toApiString() {
    switch (this) {
      case UserPlan.free:
        return 'free';
      case UserPlan.monthlyPro:
        return 'monthly_pro';
      case UserPlan.annualPro:
        return 'annual_pro';
    }
  }

  /// Parse from Firestore string
  static UserPlan fromString(String? value) {
    switch (value) {
      case 'monthly_pro':
        return UserPlan.monthlyPro;
      case 'annual_pro':
        return UserPlan.annualPro;
      default:
        return UserPlan.free;
    }
  }
}

/// User credit information model
class UserCredits {
  final int credits;
  final int maxCredits;
  final UserPlan plan;

  const UserCredits({
    required this.credits,
    required this.maxCredits,
    required this.plan,
  });

  /// Default free tier credits
  factory UserCredits.free() => const UserCredits(
        credits: 5,
        maxCredits: 5,
        plan: UserPlan.free,
      );

  /// Parse from Firestore document
  factory UserCredits.fromFirestore(Map<String, dynamic> data) {
    return UserCredits(
      credits: (data['credits'] as num?)?.toInt() ?? 0,
      maxCredits: (data['maxCredits'] as num?)?.toInt() ?? 5,
      plan: UserPlan.fromString(data['plan'] as String?),
    );
  }

  /// Check if user has enough credits
  bool hasCredits(int amount) => credits >= amount;

  /// User-friendly plan name
  String get planDisplayName {
    switch (plan) {
      case UserPlan.free:
        return 'Free';
      case UserPlan.monthlyPro:
        return 'Pro (Monthly)';
      case UserPlan.annualPro:
        return 'Pro (Annual)';
    }
  }
}

/// Service for managing user credits
///
/// SECURITY ARCHITECTURE:
/// - This service NEVER modifies credits directly in Firestore
/// - All credit mutations happen through Cloud Functions
/// - Firestore security rules BLOCK client-side credit modification
/// - Client can only READ credits for UI display
///
/// USAGE:
/// ```dart
/// final creditService = CreditService();
///
/// // Check credits before generation
/// final credits = await creditService.getCredits();
/// if (!credits.hasCredits(1)) {
///   // Show upgrade UI
///   return;
/// }
///
/// // Consume credit BEFORE AI generation
/// try {
///   await creditService.consumeCredit(1);
///   // Proceed with AI generation
/// } on InsufficientCreditsException {
///   // Show upgrade UI
/// }
/// ```
class CreditService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseFunctions _functions = FirebaseFunctions.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Get current user's document reference
  DocumentReference<Map<String, dynamic>>? get _userDoc {
    final userId = _auth.currentUser?.uid;
    if (userId == null) return null;
    return _firestore.collection('users').doc(userId);
  }

  // ============================================================
  // READ OPERATIONS (Direct Firestore access - allowed by rules)
  // ============================================================

  /// Get user's current credit information
  ///
  /// Returns [UserCredits] with current balance, max, and plan
  /// Throws if user is not logged in
  Future<UserCredits> getCredits() async {
    final doc = _userDoc;
    if (doc == null) {
      throw Exception('User not logged in');
    }

    try {
      final snapshot = await doc.get();
      if (!snapshot.exists) {
        // User document doesn't exist yet - return free defaults
        // The Cloud Function onUserCreated should create this
        debugPrint('CreditService: User document not found, returning defaults');
        return UserCredits.free();
      }

      return UserCredits.fromFirestore(snapshot.data()!);
    } catch (e) {
      debugPrint('CreditService: Error getting credits: $e');
      rethrow;
    }
  }

  /// Stream of user's credit information for real-time UI updates
  ///
  /// Use with StreamBuilder for automatic UI updates:
  /// ```dart
  /// StreamBuilder<UserCredits>(
  ///   stream: creditService.creditsStream,
  ///   builder: (context, snapshot) {
  ///     if (snapshot.hasData) {
  ///       return Text('Credits: ${snapshot.data!.credits}');
  ///     }
  ///     return CircularProgressIndicator();
  ///   },
  /// )
  /// ```
  Stream<UserCredits> get creditsStream {
    final doc = _userDoc;
    if (doc == null) {
      return Stream.value(UserCredits.free());
    }

    return doc.snapshots().map((snapshot) {
      if (!snapshot.exists) {
        return UserCredits.free();
      }
      return UserCredits.fromFirestore(snapshot.data()!);
    });
  }

  // ============================================================
  // WRITE OPERATIONS (Cloud Function calls - ONLY way to mutate)
  // ============================================================

  /// Consume credits before AI generation
  ///
  /// IMPORTANT: Call this BEFORE starting any AI image generation.
  /// This atomically deducts credits on the server side.
  ///
  /// [amount] - Number of credits to consume (usually 1)
  ///
  /// Returns remaining credits after deduction
  ///
  /// Throws:
  /// - [InsufficientCreditsException] if not enough credits
  /// - [Exception] for network or server errors
  ///
  /// Example:
  /// ```dart
  /// try {
  ///   final remaining = await creditService.consumeCredit(1);
  ///   debugPrint('Credits remaining: $remaining');
  ///   // Now safe to call AI generation
  /// } on InsufficientCreditsException catch (e) {
  ///   // Show upgrade dialog
  ///   showUpgradeDialog(context);
  /// }
  /// ```
  Future<int> consumeCredit(int amount) async {
    if (amount <= 0) {
      throw ArgumentError('Amount must be positive');
    }

    try {
      final callable = _functions.httpsCallable('consumeCredit');

      final result = await callable.call<Map<String, dynamic>>({
        'amount': amount,
      });

      final data = result.data;
      final success = data['success'] as bool? ?? false;
      final remainingCredits = (data['remainingCredits'] as num?)?.toInt() ?? 0;

      if (!success) {
        throw Exception('Credit consumption failed');
      }

      debugPrint('CreditService: Consumed $amount credit(s), remaining: $remainingCredits');
      return remainingCredits;
    } on FirebaseFunctionsException catch (e) {
      debugPrint('CreditService: Firebase function error: ${e.code} - ${e.message}');

      // Handle specific error codes
      if (e.code == 'resource-exhausted') {
        // Parse current credits from message if available
        final currentCredits = _parseCreditsFromMessage(e.message);
        throw InsufficientCreditsException(
          currentCredits: currentCredits,
          requiredCredits: amount,
        );
      }

      if (e.code == 'unauthenticated') {
        throw Exception('Please sign in to use credits');
      }

      rethrow;
    } catch (e) {
      debugPrint('CreditService: Error consuming credit: $e');
      rethrow;
    }
  }

  /// Update user's subscription plan
  ///
  /// IMPORTANT: Only call this AFTER validating the purchase with
  /// Apple/Google servers. In a production app, purchase validation
  /// should happen on the server side.
  ///
  /// [plan] - The new subscription plan
  ///
  /// Returns the new max credits for the plan
  ///
  /// Example:
  /// ```dart
  /// // After successful in-app purchase validation
  /// await creditService.setUserPlan(UserPlan.monthlyPro);
  /// ```
  Future<int> setUserPlan(UserPlan plan) async {
    try {
      final callable = _functions.httpsCallable('setUserPlan');

      final result = await callable.call<Map<String, dynamic>>({
        'plan': plan.toApiString(),
      });

      final data = result.data;
      final success = data['success'] as bool? ?? false;
      final maxCredits = (data['maxCredits'] as num?)?.toInt() ?? 5;

      if (!success) {
        throw Exception('Plan update failed');
      }

      debugPrint('CreditService: Plan updated to ${plan.toApiString()}, maxCredits: $maxCredits');
      return maxCredits;
    } on FirebaseFunctionsException catch (e) {
      debugPrint('CreditService: Firebase function error: ${e.code} - ${e.message}');

      if (e.code == 'unauthenticated') {
        throw Exception('Please sign in to update your plan');
      }

      rethrow;
    } catch (e) {
      debugPrint('CreditService: Error setting plan: $e');
      rethrow;
    }
  }

  /// Initialize credits for a new or existing user
  ///
  /// IMPORTANT: Call this after user signup/login to ensure credits are set up.
  /// This function is idempotent - safe to call multiple times.
  /// It will NOT reset credits if they already exist.
  ///
  /// Example:
  /// ```dart
  /// // After successful login
  /// await creditService.initializeCredits();
  /// ```
  Future<UserCredits> initializeCredits() async {
    try {
      final callable = _functions.httpsCallable('initializeUserCredits');

      final result = await callable.call<Map<String, dynamic>>(null);

      final data = result.data;
      final success = data['success'] as bool? ?? false;

      if (!success) {
        throw Exception('Credit initialization failed');
      }

      debugPrint(
        'CreditService: Credits initialized - '
        'already existed: ${data['alreadyInitialized']}, '
        'credits: ${data['credits']}'
      );

      return UserCredits(
        credits: (data['credits'] as num?)?.toInt() ?? 0,
        maxCredits: (data['maxCredits'] as num?)?.toInt() ?? 5,
        plan: UserPlan.fromString(data['plan'] as String?),
      );
    } on FirebaseFunctionsException catch (e) {
      debugPrint('CreditService: Firebase function error: ${e.code} - ${e.message}');

      if (e.code == 'unauthenticated') {
        throw Exception('Please sign in to initialize credits');
      }

      rethrow;
    } catch (e) {
      debugPrint('CreditService: Error initializing credits: $e');
      rethrow;
    }
  }

  /// Get user's credits from Cloud Function (bypasses cache)
  ///
  /// Use this when you need guaranteed fresh data.
  /// For normal UI display, prefer [getCredits] or [creditsStream].
  Future<UserCredits> getCreditsFromServer() async {
    try {
      final callable = _functions.httpsCallable('getUserCredits');

      final result = await callable.call<Map<String, dynamic>>(null);

      final data = result.data;
      return UserCredits(
        credits: (data['credits'] as num?)?.toInt() ?? 0,
        maxCredits: (data['maxCredits'] as num?)?.toInt() ?? 5,
        plan: UserPlan.fromString(data['plan'] as String?),
      );
    } on FirebaseFunctionsException catch (e) {
      debugPrint('CreditService: Firebase function error: ${e.code} - ${e.message}');

      if (e.code == 'unauthenticated') {
        throw Exception('Please sign in to view credits');
      }

      rethrow;
    } catch (e) {
      debugPrint('CreditService: Error getting credits from server: $e');
      rethrow;
    }
  }

  // ============================================================
  // HELPER METHODS
  // ============================================================

  /// Parse credits from error message
  int _parseCreditsFromMessage(String? message) {
    if (message == null) return 0;

    // Try to parse "You have X credits" pattern
    final regex = RegExp(r'You have (\d+) credits');
    final match = regex.firstMatch(message);
    if (match != null) {
      return int.tryParse(match.group(1) ?? '0') ?? 0;
    }

    return 0;
  }

  /// Check if user can afford an operation
  ///
  /// Convenience method that doesn't throw - returns bool
  Future<bool> canAfford(int amount) async {
    try {
      final credits = await getCredits();
      return credits.hasCredits(amount);
    } catch (e) {
      debugPrint('CreditService: Error checking credits: $e');
      return false;
    }
  }
}
