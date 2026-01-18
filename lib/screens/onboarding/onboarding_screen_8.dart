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

import '../../providers/theme_provider.dart';
import '../../services/revenuecat_service.dart';
import '../../services/credit_service.dart';
import '../../services/onboarding_service.dart';
import '../../widgets/purchase_success_screen.dart';
import '../../navigation/home_navbar.dart';

class OnboardingScreen8 extends StatefulWidget {
  const OnboardingScreen8({super.key});

  @override
  State<OnboardingScreen8> createState() => _OnboardingScreen8State();
}

class _OnboardingScreen8State extends State<OnboardingScreen8> {
  int _selectedPlan = 0; // 0 = Monthly (Best Value), 1 = 15-pack, 2 = 5-pack
  bool _isLoading = true;
  bool _isPurchasing = false;
  bool _isRestoring = false;
  bool _isVideoInitialized = false;
  bool _isSkipping = false;
  Offerings? _offerings;
  String? _error;

  final RevenueCatService _revenueCatService = RevenueCatService();
  final CreditService _creditService = CreditService();
  final OnboardingService _onboardingService = OnboardingService();
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
          _error = 'Could not load subscription options';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _handlePurchase() async {
    if (_offerings?.current == null || _isPurchasing) return;

    setState(() {
      _isPurchasing = true;
      _error = null;
    });

    try {
      // Get current credits BEFORE purchase (for animation)
      final previousCredits = await _creditService.getCredits();
      final previousCreditCount = previousCredits.credits;

      // Handle one-time credit purchases (plan == 1 or 2)
      if (_selectedPlan == 1) {
        // 15-pack
        await _handleOneTimePurchase(
          previousCreditCount: previousCreditCount,
          packageIdentifier: '\$rc_stylecredits',
          cloudFunctionName: 'handleCreditTopUp',
          creditsAmount: 15,
        );
        return;
      } else if (_selectedPlan == 2) {
        // 5-pack
        await _handleOneTimePurchase(
          previousCreditCount: previousCreditCount,
          packageIdentifier: '\$rc_stylecredits_5pack',
          cloudFunctionName: 'handleCreditTopUp5Pack',
          creditsAmount: 5,
        );
        return;
      }

      // Handle Monthly subscription (plan == 0)
      final package = _offerings!.current!.monthly;

      if (package == null) {
        throw Exception('Selected package not available');
      }

      // 1. Purchase via RevenueCat
      await _revenueCatService.purchasePackage(package);

      // 2. Wait for RevenueCat to sync data to servers (important for validation)
      debugPrint('Waiting for RevenueCat to sync purchase data...');
      await Future.delayed(const Duration(seconds: 3));

      // 3. Validate and grant credits via Cloud Function
      final functions = FirebaseFunctions.instance;
      await functions.httpsCallable('handlePurchaseSuccess').call({
        'productId': package.storeProduct.identifier,
      });

      // 4. Mark onboarding as completed with signedUpDuringOnboarding = true
      await _onboardingService.completeOnboarding(signedUp: true);

      // 5. Success! Show animated success screen
      if (mounted) {
        // Show success screen
        await PurchaseSuccessScreen.show(
          context,
          previousCredits: previousCreditCount,
          creditsAdded: 50,
          planName: 'Monthly Pro',
        );

        // Navigate to home
        if (mounted) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (context) => const HomeNavBar()),
            (route) => false,
          );
        }
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

  Future<void> _handleOneTimePurchase({
    required int previousCreditCount,
    required String packageIdentifier,
    required String cloudFunctionName,
    required int creditsAmount,
  }) async {
    try {
      // Find the consumable credit package
      final package = _offerings!.current!.availablePackages
          .where((p) => p.identifier == packageIdentifier)
          .firstOrNull;

      if (package == null) {
        throw Exception('Credit package not available');
      }

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
                  : b);

      if (transaction.transactionIdentifier.isEmpty) {
        throw Exception('Transaction ID not found in purchase response');
      }

      debugPrint('One-time purchase transaction ID: ${transaction.transactionIdentifier}');

      // 3. Process credit top-up via appropriate Cloud Function
      final functions = FirebaseFunctions.instance;
      await functions.httpsCallable(cloudFunctionName).call({
        'productId': productId,
        'transactionId': transaction.transactionIdentifier,
      });

      // 4. Mark onboarding as completed
      await _onboardingService.completeOnboarding(signedUp: false);

      // 5. Success! Show animated success screen
      if (mounted) {
        await PurchaseSuccessScreen.show(
          context,
          previousCredits: previousCreditCount,
          creditsAdded: creditsAmount,
          planName: '$creditsAmount Style Credits',
        );

        // Navigate to home
        if (mounted) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (context) => const HomeNavBar()),
            (route) => false,
          );
        }
      }
    } catch (e) {
      debugPrint('One-time purchase error: $e');
      if (mounted) {
        setState(() => _error = 'Something went wrong. Please try again.');
      }
    } finally {
      if (mounted) {
        setState(() => _isPurchasing = false);
      }
    }
  }

  Future<void> _handleRestore() async {
    if (_isRestoring) return;

    setState(() {
      _isRestoring = true;
      _error = null;
    });

    try {
      final customerInfo = await _revenueCatService.restorePurchases();

      if (_revenueCatService.hasProEntitlement(customerInfo)) {
        // Wait for RevenueCat to sync (important for validation)
        debugPrint('Waiting for RevenueCat to sync restore data...');
        await Future.delayed(const Duration(seconds: 2));

        // Sync with backend using restore-specific function (does NOT grant extra credits)
        final productId = _revenueCatService.getActiveProductId(customerInfo);
        if (productId != null) {
          final functions = FirebaseFunctions.instance;
          await functions.httpsCallable('handleRestorePurchase').call({
            'productId': productId,
          });
        }

        // Mark onboarding as completed with signedUpDuringOnboarding = true
        await _onboardingService.completeOnboarding(signedUp: true);

        if (mounted) {
          // Navigate to home
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (context) => const HomeNavBar()),
            (route) => false,
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No active subscription found.'),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Restore error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not restore purchases. Please try again.'),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isRestoring = false);
      }
    }
  }

  Future<void> _handleSkip() async {
    if (_isSkipping) return;

    setState(() {
      _isSkipping = true;
    });

    try {
      // Complete onboarding without purchase
      await _onboardingService.completeOnboarding(signedUp: false);

      if (mounted) {
        // Navigate to home
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const HomeNavBar()),
          (route) => false,
        );
      }
    } catch (e) {
      debugPrint('Skip error: $e');
      if (mounted) {
        setState(() => _isSkipping = false);
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
                  child: Transform.translate(
                    offset: const Offset(-30, 0), // Shift left to center subject (adjust as needed)
                    child: Transform.scale(
                      scale: 1.15, // Zoom in slightly (adjust as needed)
                      child: VideoPlayer(_videoController),
                    ),
                  ),
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

          // Content on top
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
              child: Column(
                children: [
                  // Header with close button
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      _buildCloseButton(accent),
                    ],
                  ),

                  const Spacer(flex: 3),

                  // Title
                  _buildTitle(colorScheme, accent, isDark),

                  const SizedBox(height: 6),

                  // Subtitle
                  _buildSubtitle(colorScheme),

                  const SizedBox(height: 10),

                  // Features
                  _buildFeatures(accent, colorScheme),

                  const SizedBox(height: 10),

                  // Credit Info
                  _buildCreditInfo(accent, colorScheme),

                  const SizedBox(height: 10),

                  // Pricing Cards
                  _buildPricingCards(colorScheme, accent, isDark, themeProvider),

                  const SizedBox(height: 6),

                  // Free tier
                  _buildFreeTier(colorScheme),

                  const SizedBox(height: 10),

                  // CTA Button
                  _buildCTAButton(accent, themeProvider),

                  const SizedBox(height: 6),

                  // Terms
                  _buildTerms(colorScheme),

                  const SizedBox(height: 4),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCloseButton(Color accent) {
    return GestureDetector(
      onTap: _isSkipping ? null : _handleSkip,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: _isSkipping
            ? SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: accent.withValues(alpha: 0.8),
                ),
              )
            : Icon(
                Icons.close,
                size: 28,
                color: Colors.white.withValues(alpha: 0.9),
              ),
      ),
    );
  }

  @override
  void dispose() {
    _videoController.dispose();
    super.dispose();
  }

  Widget _buildTitle(ColorScheme colorScheme, Color accent, bool isDark) {
    return Text(
      'Try On Any Outfit Instantly',
      textAlign: TextAlign.center,
      style: GoogleFonts.playfairDisplay(
        fontSize: 22,
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
    );
  }

  Widget _buildSubtitle(ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Text(
        'See how any outfit looks on you before you buy.',
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
    );
  }

  Widget _buildFeatures(Color accent, ColorScheme colorScheme) {
    final features = [
      'AI-powered virtual fitting room',
      'Photorealistic outfit previews',
      'Shop smarter, return less',
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: features
            .map((f) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      Icon(Icons.check_circle, size: 16, color: accent),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          f,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: Colors.white.withValues(alpha: 0.9),
                            shadows: [
                              Shadow(
                                color: Colors.black.withValues(alpha: 0.5),
                                offset: const Offset(0, 1),
                                blurRadius: 4,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ))
            .toList(),
      ),
    );
  }

  Widget _buildCreditInfo(Color accent, ColorScheme colorScheme) {
    return Column(
      children: [
        Text(
          'STYLE CREDITS',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 9,
            fontWeight: FontWeight.w700,
            color: accent,
            letterSpacing: 1.3,
            shadows: [
              Shadow(
                color: Colors.black.withValues(alpha: 0.5),
                offset: const Offset(0, 1),
                blurRadius: 4,
              ),
            ],
          ),
        ),
        const SizedBox(height: 2),
        Text(
          '1 Credit = 1 outfit try-on',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 10,
            color: Colors.white.withValues(alpha: 0.75),
            shadows: [
              Shadow(
                color: Colors.black.withValues(alpha: 0.5),
                offset: const Offset(0, 1),
                blurRadius: 4,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPricingCards(
    ColorScheme colorScheme,
    Color accent,
    bool isDark,
    ThemeProvider themeProvider,
  ) {
    // Get real prices from RevenueCat offerings
    final monthlyPackage = _offerings?.current?.monthly;
    final creditPackage15 = _offerings?.current?.availablePackages
        .where((p) => p.identifier == '\$rc_stylecredits')
        .firstOrNull;
    final creditPackage5 = _offerings?.current?.availablePackages
        .where((p) => p.identifier == '\$rc_stylecredits_5pack')
        .firstOrNull;

    final monthlyPrice = monthlyPackage?.storeProduct.priceString ?? '\$9.99';
    final credit15Price = creditPackage15?.storeProduct.priceString ?? '\$4.99';
    final credit5Price = creditPackage5?.storeProduct.priceString ?? '\$2.99';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          // Monthly Plan (Best Value)
          _buildPlanCard(
            isSelected: _selectedPlan == 0,
            title: 'Monthly Pro',
            price: monthlyPrice,
            period: 'per month',
            credits: '50 outfit try-ons / month',
            maxBalance: 'Max balance: 100 credits',
            badge: 'Best Value',
            colorScheme: colorScheme,
            accent: accent,
            isDark: isDark,
            themeProvider: themeProvider,
            onTap: () => setState(() => _selectedPlan = 0),
          ),

          const SizedBox(height: 12),

          // 15-pack credits
          _buildPlanCard(
            isSelected: _selectedPlan == 1,
            title: '15 Style Credits',
            price: credit15Price,
            period: 'one-time',
            credits: '15 AI outfit try-ons',
            maxBalance: 'Never expires',
            badge: null,
            colorScheme: colorScheme,
            accent: accent,
            isDark: isDark,
            themeProvider: themeProvider,
            onTap: () => setState(() => _selectedPlan = 1),
          ),

          const SizedBox(height: 12),

          // 5-pack credits
          _buildPlanCard(
            isSelected: _selectedPlan == 2,
            title: '5 Style Credits',
            price: credit5Price,
            period: 'one-time',
            credits: '5 AI outfit try-ons',
            maxBalance: 'Never expires',
            badge: null,
            colorScheme: colorScheme,
            accent: accent,
            isDark: isDark,
            themeProvider: themeProvider,
            onTap: () => setState(() => _selectedPlan = 2),
          ),
        ],
      ),
    );
  }

  Widget _buildPlanCard({
    required bool isSelected,
    required String title,
    required String price,
    required String period,
    required String credits,
    required String maxBalance,
    required String? badge,
    required ColorScheme colorScheme,
    required Color accent,
    required bool isDark,
    required ThemeProvider themeProvider,
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
                // Plan details
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
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                price,
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 19,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                              Text(
                                period,
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 11,
                                  color: Colors.white.withValues(alpha: 0.7),
                                ),
                              ),
                            ],
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
                        maxBalance,
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

          // Discount badge
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

  Widget _buildFreeTier(ColorScheme colorScheme) {
    return Text(
      'Free users get 2 outfit try-ons per month',
      style: GoogleFonts.plusJakartaSans(
        fontSize: 10,
        color: Colors.white.withValues(alpha: 0.6),
        shadows: [
          Shadow(
            color: Colors.black.withValues(alpha: 0.5),
            offset: const Offset(0, 1),
            blurRadius: 4,
          ),
        ],
      ),
    );
  }

  Widget _buildCTAButton(Color accent, ThemeProvider themeProvider) {
    String buttonText;
    if (_selectedPlan == 0) {
      buttonText = 'Start Monthly Plan';
    } else if (_selectedPlan == 1) {
      buttonText = 'Purchase 15 Credits';
    } else {
      buttonText = 'Purchase 5 Credits';
    }
    final isDisabled = _isLoading || _isPurchasing || _offerings?.current == null;

    final textColor = ThemeData.estimateBrightnessForColor(accent) == Brightness.light
        ? Colors.black
        : Colors.white;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 0),
      child: Column(
        children: [
          // Error message
          if (_error != null) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                _error!,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 11,
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
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: accent.withValues(alpha: 0.35),
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
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: textColor,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Processing...',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: textColor,
                        ),
                      ),
                    ] else if (_isLoading) ...[
                      SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: textColor,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Loading...',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: textColor,
                        ),
                      ),
                    ] else ...[
                      Text(
                        buttonText,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: textColor,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        Icons.arrow_forward,
                        size: 18,
                        color: textColor,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTerms(ColorScheme colorScheme) {
    final accent = colorScheme.secondary;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          RichText(
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
                const TextSpan(
                  text: 'Subscriptions auto-renew. Cancel anytime in settings.\n',
                ),
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
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Skip for Now button
              GestureDetector(
                onTap: _isSkipping ? null : _handleSkip,
                child: _isSkipping
                    ? SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: accent.withValues(alpha: 0.8),
                        ),
                      )
                    : Text(
                        'Skip for Now',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: Colors.white.withValues(alpha: 0.7),
                          shadows: [
                            Shadow(
                              color: Colors.black.withValues(alpha: 0.5),
                              offset: const Offset(0, 1),
                              blurRadius: 4,
                            ),
                          ],
                        ),
                      ),
              ),

              const SizedBox(width: 20),

              // Restore button
              GestureDetector(
                onTap: _isRestoring ? null : _handleRestore,
                child: _isRestoring
                    ? SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: accent.withValues(alpha: 0.8),
                        ),
                      )
                    : Text(
                        'Restore',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: accent,
                          decoration: TextDecoration.underline,
                          decorationColor: accent,
                          shadows: [
                            Shadow(
                              color: Colors.black.withValues(alpha: 0.5),
                              offset: const Offset(0, 1),
                              blurRadius: 4,
                            ),
                          ],
                        ),
                      ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
