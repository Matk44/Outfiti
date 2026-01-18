import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';

/// Utility class for detecting platform capabilities and OS versions
/// Used to determine if cupertino_native (Liquid Glass) navigation is supported
class PlatformDetection {
  static final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();

  /// Check if the current iOS device supports cupertino_native
  /// Requires iOS 14.0 or higher (matches cupertino_native package requirements)
  static Future<bool> isSupportedIOS() async {
    if (!Platform.isIOS) return false;

    try {
      final iosInfo = await _deviceInfo.iosInfo;
      final majorVersion =
          int.tryParse(iosInfo.systemVersion.split('.').first) ?? 0;

      // Require iOS 14+ for cupertino_native support (package minimum)
      return majorVersion >= 14;
    } catch (e) {
      // If we can't determine the version, fall back to safe default
      return false;
    }
  }

  /// Check if the current macOS device supports cupertino_native
  /// Requires macOS 11.0 (Big Sur) or higher
  static Future<bool> isSupportedMacOS() async {
    if (!Platform.isMacOS) return false;

    try {
      final macInfo = await _deviceInfo.macOsInfo;
      final majorVersion =
          int.tryParse(macInfo.osRelease.split('.').first) ?? 0;

      // Require macOS 11+ (Big Sur) for cupertino_native support
      return majorVersion >= 11;
    } catch (e) {
      // If we can't determine the version, fall back to safe default
      return false;
    }
  }

  /// Combined check: returns true if cupertino_native should be used
  /// Only returns true on iOS 14+ or macOS 11+
  static Future<bool> shouldUseCupertinoNative() async {
    if (Platform.isIOS) return await isSupportedIOS();
    if (Platform.isMacOS) return await isSupportedMacOS();
    return false;
  }
}
