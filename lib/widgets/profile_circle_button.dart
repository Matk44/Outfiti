import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../providers/theme_provider.dart';
import '../services/user_profile_service.dart';
import '../services/credit_service.dart';
import 'paywall_modal.dart';

/// Profile circle button with credits badge that appears in AppBar
/// Displays user's profile image with credits in a combined container
class ProfileCircleButton extends StatelessWidget {
  final UserProfileService _profileService = UserProfileService();
  final CreditService _creditService = CreditService();

  /// Whether to show credits alongside the profile picture
  final bool showCredits;

  ProfileCircleButton({super.key, this.showCredits = true});

  @override
  Widget build(BuildContext context) {
    final stream = _profileService.getUserProfileStream();
    if (stream == null) {
      // No user logged in, show default avatar
      return Consumer<ThemeProvider>(
        builder: (context, themeProvider, child) {
          return _buildProfileCircleOnly(themeProvider, '');
        },
      );
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snapshot) {
        final profileData = snapshot.data?.data();
        final profileImageUrl = profileData?['profileImageUrl'] ?? '';

        return Consumer<ThemeProvider>(
          builder: (context, themeProvider, child) {
            if (showCredits) {
              return _buildWithCredits(context, themeProvider, profileImageUrl);
            }
            return _buildProfileCircleOnly(themeProvider, profileImageUrl);
          },
        );
      },
    );
  }

  /// Builds the combined credits + profile container
  Widget _buildWithCredits(
    BuildContext context,
    ThemeProvider themeProvider,
    String profileImageUrl,
  ) {
    return StreamBuilder<UserCredits>(
      stream: _creditService.creditsStream,
      builder: (context, creditsSnapshot) {
        final credits = creditsSnapshot.data?.credits ?? 0;

        // Determine color based on credit level
        final Color creditColor;
        final Color borderColor;
        if (credits == 0) {
          creditColor = Colors.red;
          borderColor = Colors.red.withValues(alpha: 0.5);
        } else if (credits < 10) {
          creditColor = Colors.orange;
          borderColor = Colors.orange.withValues(alpha: 0.5);
        } else {
          creditColor = themeProvider.accentColor;
          borderColor = themeProvider.accentColor.withValues(alpha: 0.5);
        }

        return Container(
          padding: const EdgeInsets.only(left: 12, top: 6, bottom: 6, right: 6),
          decoration: BoxDecoration(
            color: themeProvider.surfaceColor,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: borderColor,
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: creditColor.withValues(alpha: 0.1),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Credits section (tappable for upgrade modal)
              GestureDetector(
                onTap: () {
                  // Show placeholder modal for pricing/upgrade (paywall)
                  _showUpgradeModal(context, themeProvider);
                },
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      'CREDITS',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: creditColor,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 1),
                    // Animated credit number
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      transitionBuilder: (Widget child, Animation<double> animation) {
                        return ScaleTransition(
                          scale: animation,
                          child: FadeTransition(
                            opacity: animation,
                            child: child,
                          ),
                        );
                      },
                      child: Text(
                        '$credits',
                        key: ValueKey<int>(credits),
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: creditColor,
                          height: 1.0,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              // Profile circle
              _buildProfileCircle(themeProvider, profileImageUrl, size: 40),
            ],
          ),
        );
      },
    );
  }

  /// Shows the paywall modal
  void _showUpgradeModal(BuildContext context, ThemeProvider themeProvider) {
    PaywallModal.show(context);
  }

  /// Builds just the profile circle without credits
  Widget _buildProfileCircleOnly(ThemeProvider themeProvider, String profileImageUrl) {
    return Container(
      margin: const EdgeInsets.only(right: 16),
      child: _buildProfileCircle(themeProvider, profileImageUrl, size: 40),
    );
  }

  /// Builds the circular profile image
  Widget _buildProfileCircle(
    ThemeProvider themeProvider,
    String profileImageUrl, {
    required double size,
  }) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: themeProvider.surfaceColor,
        border: Border.all(
          color: themeProvider.accentColor,
          width: 2,
        ),
      ),
      child: ClipOval(
        child: profileImageUrl.isNotEmpty
            ? Image.network(
                profileImageUrl,
                width: size,
                height: size,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) =>
                    _buildPlaceholder(themeProvider, size),
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return Container(
                    color: themeProvider.surfaceColor,
                    child: Center(
                      child: SizedBox(
                        width: size * 0.4,
                        height: size * 0.4,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: themeProvider.accentColor,
                          value: loadingProgress.expectedTotalBytes != null
                              ? loadingProgress.cumulativeBytesLoaded /
                                  loadingProgress.expectedTotalBytes!
                              : null,
                        ),
                      ),
                    ),
                  );
                },
              )
            : _buildPlaceholder(themeProvider, size),
      ),
    );
  }

  Widget _buildPlaceholder(ThemeProvider themeProvider, double size) {
    return Container(
      width: size,
      height: size,
      child: SvgPicture.asset(
        'assets/icons/profile.svg',
        width: size,
        height: size,
        fit: BoxFit.cover,
      ),
    );
  }
}
