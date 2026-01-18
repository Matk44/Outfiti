import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:video_player/video_player.dart';
import 'package:url_launcher/url_launcher.dart';

import '../providers/theme_provider.dart';
import '../services/revenuecat_service.dart';
import '../services/credit_service.dart';
import 'purchase_success_screen.dart';

/// Credit Top-Up Modal for All Users
/// Allows users to purchase additional style credits:
/// - 15 credits for $4.99 (Best Value)
/// - 5 credits for $2.99
class CreditTopUpModal extends StatefulWidget {
  const CreditTopUpModal({super.key});

  static Future<void> show(BuildContext context) {
    return Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierDismissible: true,
        barrierColor: Colors.black54,
        pageBuilder: (context, animation, secondaryAnimation) {
          return const CreditTopUpModal();
        },
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.03),
                end: Offset.zero,
              ).animate(CurvedAnimation(
                parent: animation,
                curve: Curves.easeOutCubic,
              )),
              child: child,
            ),
          );
        },
        transitionDuration: const Duration(milliseconds: 300),
        reverseTransitionDuration: const Duration(milliseconds: 200),
      ),
    );
  }

  @override
  State<CreditTopUpModal> createState() => _CreditTopUpModalState();
}

class _CreditTopUpModalState extends State<CreditTopUpModal> {
  int _selectedPack = 0; // 0 = 15-pack (Best Value), 1 = 5-pack
  bool _isLoading = true;
  bool _isPurchasing = false;
  bool _isVideoInitialized = false;
  Offerings? _offerings;
  String? _error;

  final RevenueCatService _revenueCatService = RevenueCatService();
  final CreditService _creditService = CreditService();
  late VideoPlayerController _videoController;

  @override
  void initState() {
    super.initState();
    _initializeVideo();
    _loadOfferings();
  }

  Future<void> _initializeVideo() async {
    _videoController = VideoPlayerController.asset('assets/videos/splash_video.mp4');

    try {
      await _videoController.initialize();
      if (mounted) {
        setState(() {
          _isVideoInitialized = true;
        });

        // Play the video once
        _videoController.play();

        // Listen for video completion and pause on final frame
        _videoController.addListener(() {
          if (_videoController.value.position >= _videoController.value.duration) {
            if (mounted) {
              _videoController.pause();
            }
          }
        });
      }
    } catch (e) {
      debugPrint('Error initializing video: $e');
    }
  }

  Future<void> _loadOfferings() async {
    try {
      // Get current Firebase user ID
      final firebaseUid = FirebaseAuth.instance.currentUser?.uid;
      if (firebaseUid == null) {
        throw Exception('User not authenticated');
      }

      // Load offerings with Firebase UID to ensure proper user tracking
      final offerings = await _revenueCatService.getOfferings(firebaseUid: firebaseUid);
      if (mounted) {
        setState(() {
          _offerings = offerings;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading offerings: $e');
      if (mounted) {
        setState(() {
          _error = 'Could not load credit packages';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _handlePurchase() async {
    if (_offerings?.current == null || _isPurchasing) return;

    // Determine which package to purchase based on selection
    final packageIdentifier = _selectedPack == 0 ? '\$rc_stylecredits' : '\$rc_stylecredits_5pack';
    final creditsAmount = _selectedPack == 0 ? 15 : 5;
    final cloudFunctionName = _selectedPack == 0 ? 'handleCreditTopUp' : 'handleCreditTopUp5Pack';

    // Find the selected credit package
    final package = _offerings!.current!.availablePackages
        .where((p) => p.identifier == packageIdentifier)
        .firstOrNull;

    if (package == null) {
      setState(() => _error = 'Credit package not available');
      return;
    }

    setState(() {
      _isPurchasing = true;
      _error = null;
    });

    try {
      // Get current credits BEFORE purchase (for animation)
      final previousCredits = await _creditService.getCredits();
      final previousCreditCount = previousCredits.credits;

      // 1. Purchase via RevenueCat
      final customerInfo = await _revenueCatService.purchasePackage(package);

      // 2. Extract transaction ID from the purchase
      final productId = package.storeProduct.identifier;
      final nonSubTransactions = customerInfo.nonSubscriptionTransactions;

      // Find the most recent transaction for this product
      final transaction = nonSubTransactions
          .where((t) => t.productIdentifier == productId)
          .reduce((a, b) =>
              DateTime.parse(a.purchaseDate).isAfter(DateTime.parse(b.purchaseDate))
                  ? a
                  : b
          );

      if (transaction.transactionIdentifier.isEmpty) {
        throw Exception('Transaction ID not found in purchase response');
      }

      debugPrint('Top-up transaction ID: ${transaction.transactionIdentifier}');

      // 3. Process credit top-up via appropriate Cloud Function
      final functions = FirebaseFunctions.instance;
      await functions.httpsCallable(cloudFunctionName).call({
        'productId': productId,
        'transactionId': transaction.transactionIdentifier,
      });

      // 4. Success! Show animated success screen
      if (mounted) {
        // Close top-up modal first
        Navigator.of(context).pop();

        // Then show success screen with animated counter
        await PurchaseSuccessScreen.show(
          context,
          previousCredits: previousCreditCount,
          creditsAdded: creditsAmount,
          planName: '$creditsAmount Style Credits',
          isTopUp: true,
        );
      }
    } on PlatformException catch (e) {
      // Check if user cancelled
      final errorCode = PurchasesErrorHelper.getErrorCode(e);
      if (errorCode != PurchasesErrorCode.purchaseCancelledError) {
        if (mounted) {
          setState(() => _error = 'Purchase failed. Please try again.');
        }
      }
    } catch (e) {
      debugPrint('Purchase error: $e');
      if (mounted) {
        setState(() => _error = 'Something went wrong. Please try again.');
      }
    } finally {
      if (mounted) {
        setState(() => _isPurchasing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final colorScheme = Theme.of(context).colorScheme;
    final accent = colorScheme.secondary;
    final isDark = themeProvider.isDarkTheme;
    final theme = themeProvider.currentThemeColors;

    return Scaffold(
      body: Stack(
        children: [
          // Full-screen background video
          if (_isVideoInitialized)
            SizedBox.expand(
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: _videoController.value.size.width,
                  height: _videoController.value.size.height,
                  child: VideoPlayer(_videoController),
                ),
              ),
            ),

          // Fallback gradient background if video not loaded
          if (!_isVideoInitialized)
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: isDark
                      ? [theme['background']!, theme['primary']!]
                      : [theme['background']!, theme['background']!],
                ),
              ),
            ),

          // Dark gradient overlay for readability
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.3),
                  Colors.black.withValues(alpha: 0.5),
                  Colors.black.withValues(alpha: 0.7),
                ],
              ),
            ),
          ),

          // Content on top (non-scrollable)
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
              child: Column(
                children: [
                  // Header with close button
                  Align(
                    alignment: Alignment.centerLeft,
                    child: _buildCloseButton(colorScheme, isDark),
                  ),

                  const Spacer(flex: 1),

                  // Title
                  Text(
                    'Get More Outfit Try-Ons',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.playfairDisplay(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      height: 1.2,
                      shadows: [
                        Shadow(
                          color: Colors.black.withValues(alpha: 0.5),
                          offset: const Offset(0, 2),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 8),

                  // Subtitle
                  Text(
                    'Keep exploring new looks with extra Style Credits.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.85),
                      height: 1.3,
                      shadows: [
                        Shadow(
                          color: Colors.black.withValues(alpha: 0.5),
                          offset: const Offset(0, 1),
                          blurRadius: 4,
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Credit Package Cards
                  _buildPackageCards(colorScheme, accent, isDark, themeProvider),

                  const SizedBox(height: 16),

                  // Purchase Button
                  _buildPurchaseButton(accent, themeProvider),

                  const SizedBox(height: 8),

                  // Fine print
                  Text(
                    'Credits are added instantly and never expire.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 9,
                      color: Colors.white.withValues(alpha: 0.5),
                      height: 1.3,
                      shadows: [
                        Shadow(
                          color: Colors.black.withValues(alpha: 0.5),
                          offset: const Offset(0, 1),
                          blurRadius: 4,
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 8),

                  // Terms
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: RichText(
                      textAlign: TextAlign.center,
                      text: TextSpan(
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 9,
                          color: Colors.white.withValues(alpha: 0.5),
                          height: 1.3,
                          shadows: [
                            Shadow(
                              color: Colors.black.withValues(alpha: 0.5),
                              offset: const Offset(0, 1),
                              blurRadius: 4,
                            ),
                          ],
                        ),
                        children: [
                          TextSpan(
                            text: 'Terms of Use',
                            style: TextStyle(
                              color: accent,
                              decoration: TextDecoration.underline,
                              decorationColor: accent,
                            ),
                            recognizer: TapGestureRecognizer()
                              ..onTap = () async {
                                final uri = Uri.parse('https://www.apple.com/legal/internet-services/itunes/dev/stdeula/');
                                if (await canLaunchUrl(uri)) {
                                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                                }
                              },
                          ),
                          const TextSpan(text: ' & '),
                          TextSpan(
                            text: 'Privacy Policy',
                            style: TextStyle(
                              color: accent,
                              decoration: TextDecoration.underline,
                              decorationColor: accent,
                            ),
                            recognizer: TapGestureRecognizer()
                              ..onTap = () async {
                                final uri = Uri.parse('https://matk44.github.io/outfiti-support/outfiti_privacy_policy.html');
                                if (await canLaunchUrl(uri)) {
                                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                                }
                              },
                          ),
                        ],
                      ),
                    ),
                  ),

                  const Spacer(flex: 1),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPackageCards(
    ColorScheme colorScheme,
    Color accent,
    bool isDark,
    ThemeProvider themeProvider,
  ) {
    // Get real prices from RevenueCat offerings
    final pack15 = _offerings?.current?.availablePackages
        .where((p) => p.identifier == '\$rc_stylecredits')
        .firstOrNull;
    final pack5 = _offerings?.current?.availablePackages
        .where((p) => p.identifier == '\$rc_stylecredits_5pack')
        .firstOrNull;

    final price15 = pack15?.storeProduct.priceString ?? '\$4.99';
    final price5 = pack5?.storeProduct.priceString ?? '\$2.99';

    return Column(
      children: [
        // 15-pack (Best Value)
        _buildPackCard(
          isSelected: _selectedPack == 0,
          title: '15 Style Credits',
          price: price15,
          credits: '15 AI outfit try-ons',
          subtitle: 'Never expires',
          badge: 'Best Value',
          colorScheme: colorScheme,
          accent: accent,
          isDark: isDark,
          onTap: () => setState(() => _selectedPack = 0),
        ),

        const SizedBox(height: 12),

        // 5-pack
        _buildPackCard(
          isSelected: _selectedPack == 1,
          title: '5 Style Credits',
          price: price5,
          credits: '5 AI outfit try-ons',
          subtitle: 'Never expires',
          badge: null,
          colorScheme: colorScheme,
          accent: accent,
          isDark: isDark,
          onTap: () => setState(() => _selectedPack = 1),
        ),
      ],
    );
  }

  Widget _buildPackCard({
    required bool isSelected,
    required String title,
    required String price,
    required String credits,
    required String subtitle,
    required String? badge,
    required ColorScheme colorScheme,
    required Color accent,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isSelected
                  ? Colors.white.withValues(alpha: 0.15)
                  : Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isSelected ? accent : Colors.white.withValues(alpha: 0.2),
                width: 2,
              ),
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color: accent.withValues(alpha: 0.3),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                    ]
                  : null,
            ),
            child: Row(
              children: [
                // Pack details
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Title and price row
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                          Text(
                            price,
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      // Credits info
                      Row(
                        children: [
                          Icon(
                            Icons.toll,
                            size: 15,
                            color: accent,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            credits,
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 11,
                              color: Colors.white.withValues(alpha: 0.85),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 10,
                          color: Colors.white.withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 12),

                // Radio indicator
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isSelected ? accent : Colors.white.withValues(alpha: 0.4),
                      width: 2,
                    ),
                    color: isSelected ? accent : Colors.transparent,
                  ),
                  child: isSelected
                      ? Center(
                          child: Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white,
                            ),
                          ),
                        )
                      : null,
                ),
              ],
            ),
          ),

          // Badge
          if (badge != null)
            Positioned(
              top: -10,
              right: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [accent, accent.withValues(alpha: 0.8)],
                  ),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: accent.withValues(alpha: 0.5),
                      blurRadius: 12,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Text(
                  badge,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: ThemeData.estimateBrightnessForColor(accent) == Brightness.light
                        ? Colors.black
                        : Colors.white,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _videoController.dispose();
    super.dispose();
  }

  Widget _buildCloseButton(ColorScheme colorScheme, bool isDark) {
    return GestureDetector(
      onTap: () => Navigator.of(context).pop(),
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: isDark
              ? Colors.white.withValues(alpha: 0.1)
              : Colors.black.withValues(alpha: 0.05),
          shape: BoxShape.circle,
        ),
        child: Icon(
          Icons.close,
          size: 22,
          color: colorScheme.onSurface.withValues(alpha: 0.7),
        ),
      ),
    );
  }

  Widget _buildPurchaseButton(Color accent, ThemeProvider themeProvider) {
    final isDisabled = _isLoading || _isPurchasing || _offerings?.current == null;
    final buttonText = _selectedPack == 0 ? 'Purchase 15 Credits' : 'Purchase 5 Credits';

    final textColor =
        ThemeData.estimateBrightnessForColor(accent) == Brightness.light
            ? Colors.black
            : Colors.white;

    return Column(
      children: [
        // Error message
        if (_error != null) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              _error!,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                color: Colors.red,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],

        // Purchase button
        GestureDetector(
          onTap: isDisabled ? null : _handlePurchase,
          child: AnimatedOpacity(
            opacity: isDisabled ? 0.6 : 1.0,
            duration: const Duration(milliseconds: 200),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    accent,
                    accent.withValues(alpha: 0.85),
                  ],
                ),
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: accent.withValues(alpha: 0.4),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (_isPurchasing) ...[
                    SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: textColor,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Processing...',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: textColor,
                      ),
                    ),
                  ] else if (_isLoading) ...[
                    SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: textColor,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Loading...',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: textColor,
                      ),
                    ),
                  ] else ...[
                    Icon(
                      Icons.add_circle_outline,
                      size: 18,
                      color: textColor,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      buttonText,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: textColor,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
