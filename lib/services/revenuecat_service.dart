import 'package:flutter/foundation.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

/// Service wrapper for RevenueCat SDK
/// Handles subscription management and purchase flows
///
/// IMPORTANT: This is a singleton to ensure proper SDK lifecycle management.
/// The SDK is configured ONCE per app session (anonymous mode), then users
/// are identified via Purchases.logIn(firebaseUid).
class RevenueCatService {
  // Singleton instance
  static final RevenueCatService _instance = RevenueCatService._internal();
  factory RevenueCatService() => _instance;
  RevenueCatService._internal();

  // RevenueCat API Key (iOS)
  static const String _apiKey = 'appl_kEpfculqaDTCGLbhEqUrSqOBTcA';

  // Entitlement ID configured in RevenueCat dashboard
  // IMPORTANT: This must match exactly (case-sensitive) with RevenueCat dashboard
  static const String _entitlementId = 'Pro';

  // Track SDK state - configured ONCE per app session, never reset
  bool _isConfigured = false;
  String? _currentUserId;

  /// Configure RevenueCat SDK ONCE per app session
  /// This is called automatically by other methods - you don't need to call it directly
  ///
  /// IMPORTANT: Configures in anonymous mode. Use login() to identify users.
  Future<void> _ensureConfigured() async {
    if (_isConfigured) {
      return; // Already configured, skip
    }

    try {
      // Configure anonymously - DO NOT specify appUserID
      // Users will be identified later via Purchases.logIn()
      await Purchases.configure(PurchasesConfiguration(_apiKey));
      _isConfigured = true;
      debugPrint('RevenueCat SDK configured (anonymous mode)');
    } catch (e) {
      debugPrint('Error configuring RevenueCat: $e');
      rethrow;
    }
  }

  /// Login/Identify user with Firebase UID
  /// This creates an alias linking the anonymous RevenueCat user to your Firebase user
  ///
  /// IMPORTANT: This should be called when the user signs in to your app
  Future<LogInResult> login(String firebaseUid) async {
    // Ensure SDK is configured first (anonymous)
    await _ensureConfigured();

    try {
      // Check if already logged in as this user
      if (_currentUserId == firebaseUid) {
        final customerInfo = await Purchases.getCustomerInfo();
        debugPrint('RevenueCat already logged in as: $firebaseUid');
        return LogInResult(
          customerInfo: customerInfo,
          created: false,
        );
      }

      // CRITICAL: Always call Purchases.logIn() to link anonymous user to Firebase UID
      // This creates the alias that allows backend to query by Firebase UID
      debugPrint('Logging in to RevenueCat as: $firebaseUid');
      final result = await Purchases.logIn(firebaseUid);
      _currentUserId = firebaseUid;
      debugPrint('RevenueCat login successful for user: $firebaseUid');
      return result;
    } catch (e) {
      debugPrint('Error logging in to RevenueCat: $e');
      rethrow;
    }
  }

  /// Logout RevenueCat user
  /// Returns to anonymous state but keeps SDK configured
  ///
  /// IMPORTANT: The SDK stays configured - we never re-configure after logout
  Future<void> logout() async {
    if (!_isConfigured) {
      return; // Not configured, nothing to do
    }

    try {
      await Purchases.logOut();
      _currentUserId = null;
      // CRITICAL: Do NOT set _isConfigured = false!
      // The SDK remains configured, just returns to anonymous state
      debugPrint('RevenueCat user logged out (returned to anonymous mode)');
    } catch (e) {
      debugPrint('Error logging out from RevenueCat: $e');
      // Don't rethrow - logout errors shouldn't block Firebase logout
    }
  }

  /// Get available subscription packages
  ///
  /// IMPORTANT: If firebaseUid is provided and user not already logged in,
  /// this will automatically call login() to identify the user first
  Future<Offerings?> getOfferings({String? firebaseUid}) async {
    await _ensureConfigured();

    // If Firebase UID provided and different from current, login first
    if (firebaseUid != null && _currentUserId != firebaseUid) {
      await login(firebaseUid);
    }

    try {
      final offerings = await Purchases.getOfferings();
      debugPrint('RevenueCat offerings fetched: ${offerings.current?.identifier}');
      return offerings;
    } catch (e) {
      debugPrint('Error fetching offerings: $e');
      rethrow;
    }
  }

  /// Purchase a subscription package
  /// Returns CustomerInfo on success
  Future<CustomerInfo> purchasePackage(Package package) async {
    await _ensureConfigured();

    try {
      final result = await Purchases.purchasePackage(package);
      debugPrint('Purchase successful: ${package.storeProduct.identifier}');
      return result;
    } catch (e) {
      debugPrint('Purchase error: $e');
      rethrow;
    }
  }

  /// Restore previous purchases
  /// Use when user reinstalls app or logs in on new device
  Future<CustomerInfo> restorePurchases() async {
    await _ensureConfigured();

    try {
      final customerInfo = await Purchases.restorePurchases();
      debugPrint('Purchases restored successfully');
      return customerInfo;
    } catch (e) {
      debugPrint('Error restoring purchases: $e');
      rethrow;
    }
  }

  /// Get current customer info (entitlements, subscription status)
  ///
  /// IMPORTANT: If firebaseUid is provided and user not already logged in,
  /// this will automatically call login() to identify the user first
  Future<CustomerInfo> getCustomerInfo({String? firebaseUid}) async {
    await _ensureConfigured();

    // If Firebase UID provided and different from current, login first
    if (firebaseUid != null && _currentUserId != firebaseUid) {
      await login(firebaseUid);
    }

    return await Purchases.getCustomerInfo();
  }

  /// Check if user has active Pro subscription
  bool hasProEntitlement(CustomerInfo customerInfo) {
    return customerInfo.entitlements.active.containsKey(_entitlementId);
  }

  /// Get the active product ID for the Pro entitlement
  /// Returns null if no active subscription
  String? getActiveProductId(CustomerInfo customerInfo) {
    final entitlement = customerInfo.entitlements.active[_entitlementId];
    return entitlement?.productIdentifier;
  }

  /// Get expiration date for Pro subscription
  /// Returns null if no active subscription
  DateTime? getExpirationDate(CustomerInfo customerInfo) {
    final entitlement = customerInfo.entitlements.active[_entitlementId];
    if (entitlement?.expirationDate != null) {
      return DateTime.parse(entitlement!.expirationDate!);
    }
    return null;
  }

  /// Check if subscription will renew
  bool willRenew(CustomerInfo customerInfo) {
    final entitlement = customerInfo.entitlements.active[_entitlementId];
    return entitlement?.willRenew ?? false;
  }
}
