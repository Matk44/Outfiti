import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../providers/theme_provider.dart';

/// Full-screen overlay shown after successful purchase
/// Displays animated credit counter from previous to new balance
class PurchaseSuccessScreen extends StatefulWidget {
  final int previousCredits;
  final int creditsAdded;
  final String planName; // "Monthly Pro", "Annual Pro", or "15 Style Credits"
  final bool isTopUp; // true for credit top-up, false for subscription

  const PurchaseSuccessScreen({
    super.key,
    required this.previousCredits,
    required this.creditsAdded,
    required this.planName,
    this.isTopUp = false,
  });

  /// Show the success screen as a full-screen modal
  static Future<void> show(
    BuildContext context, {
    required int previousCredits,
    required int creditsAdded,
    required String planName,
    bool isTopUp = false,
  }) {
    return Navigator.of(context).push(
      PageRouteBuilder(
        opaque: true,
        barrierDismissible: false,
        pageBuilder: (context, animation, secondaryAnimation) {
          return PurchaseSuccessScreen(
            previousCredits: previousCredits,
            creditsAdded: creditsAdded,
            planName: planName,
            isTopUp: isTopUp,
          );
        },
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: animation,
            child: child,
          );
        },
        transitionDuration: const Duration(milliseconds: 400),
        reverseTransitionDuration: const Duration(milliseconds: 300),
      ),
    );
  }

  @override
  State<PurchaseSuccessScreen> createState() => _PurchaseSuccessScreenState();
}

class _PurchaseSuccessScreenState extends State<PurchaseSuccessScreen>
    with TickerProviderStateMixin {
  late AnimationController _counterController;
  late Animation<double> _counterAnimation;
  late int _displayedCredits;

  @override
  void initState() {
    super.initState();
    _displayedCredits = widget.previousCredits;

    // Setup counter animation
    _counterController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );

    _counterAnimation = Tween<double>(
      begin: widget.previousCredits.toDouble(),
      end: (widget.previousCredits + widget.creditsAdded).toDouble(),
    ).animate(CurvedAnimation(
      parent: _counterController,
      curve: Curves.easeOutCubic,
    ));

    _counterAnimation.addListener(() {
      setState(() {
        _displayedCredits = _counterAnimation.value.round();
      });
    });

    // Start counter animation after a short delay
    Future.delayed(const Duration(milliseconds: 800), () {
      if (mounted) {
        _counterController.forward();
      }
    });
  }

  @override
  void dispose() {
    _counterController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final colorScheme = Theme.of(context).colorScheme;
    final accent = colorScheme.secondary;
    final screenSize = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: themeProvider.backgroundColor,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            children: [
              const Spacer(flex: 2),

              // Success checkmark with glow
              _buildSuccessIcon(accent)
                  .animate()
                  .scale(
                    begin: const Offset(0.5, 0.5),
                    end: const Offset(1.0, 1.0),
                    duration: 600.ms,
                    curve: Curves.elasticOut,
                  )
                  .fadeIn(duration: 400.ms),

              const SizedBox(height: 32),

              // Success title
              Text(
                widget.isTopUp ? 'Credits Added!' : 'Welcome to Pro!',
                style: GoogleFonts.playfairDisplay(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: themeProvider.textPrimaryColor,
                ),
                textAlign: TextAlign.center,
              )
                  .animate()
                  .fadeIn(delay: 200.ms, duration: 400.ms)
                  .slideY(begin: 0.2, end: 0, duration: 400.ms),

              const SizedBox(height: 8),

              // Plan name
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  widget.planName,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: accent,
                  ),
                ),
              )
                  .animate()
                  .fadeIn(delay: 300.ms, duration: 400.ms)
                  .scale(begin: const Offset(0.8, 0.8), duration: 400.ms),

              const SizedBox(height: 48),

              // Credits card with animated counter
              _buildCreditsCard(themeProvider, accent, screenSize)
                  .animate()
                  .fadeIn(delay: 500.ms, duration: 500.ms)
                  .slideY(begin: 0.3, end: 0, duration: 500.ms),

              const SizedBox(height: 24),

              // Credits added info
              Text(
                '+${widget.creditsAdded} credits added',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: Colors.green,
                ),
              )
                  .animate()
                  .fadeIn(delay: 1800.ms, duration: 400.ms)
                  .shimmer(delay: 2000.ms, duration: 1500.ms),

              const Spacer(flex: 2),

              // Continue button
              _buildContinueButton(accent, themeProvider)
                  .animate()
                  .fadeIn(delay: 2200.ms, duration: 400.ms)
                  .slideY(begin: 0.3, end: 0, duration: 400.ms),

              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSuccessIcon(Color accent) {
    return Container(
      width: 100,
      height: 100,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accent,
            accent.withValues(alpha: 0.7),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.4),
            blurRadius: 30,
            spreadRadius: 5,
          ),
        ],
      ),
      child: Icon(
        Icons.check_rounded,
        size: 56,
        color: ThemeData.estimateBrightnessForColor(accent) == Brightness.light
            ? Colors.black
            : Colors.white,
      ),
    );
  }

  Widget _buildCreditsCard(
    ThemeProvider themeProvider,
    Color accent,
    Size screenSize,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      decoration: BoxDecoration(
        color: themeProvider.surfaceColor,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: accent.withValues(alpha: 0.3),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.15),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          // Credits GIF
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: accent,
                width: 3,
              ),
              boxShadow: [
                BoxShadow(
                  color: accent.withValues(alpha: 0.3),
                  blurRadius: 16,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: ClipOval(
              child: Image.asset(
                'assets/icons/credits.gif',
                width: 80,
                height: 80,
                fit: BoxFit.cover,
              ),
            ),
          ),

          const SizedBox(height: 20),

          // Label
          Text(
            'YOUR STYLE CREDITS',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: accent,
              letterSpacing: 1.5,
            ),
          ),

          const SizedBox(height: 12),

          // Animated counter
          Text(
            '$_displayedCredits',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 64,
              fontWeight: FontWeight.bold,
              color: accent,
              height: 1.0,
            ),
          ),

          const SizedBox(height: 8),

          // Subtitle
          Text(
            '1 credit = 1 AI hairstyle try-on',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              color: themeProvider.textSecondaryColor.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContinueButton(Color accent, ThemeProvider themeProvider) {
    final textColor = ThemeData.estimateBrightnessForColor(accent) == Brightness.light
        ? Colors.black
        : Colors.white;

    return GestureDetector(
      onTap: () => Navigator.of(context).pop(),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              accent,
              accent.withValues(alpha: 0.8),
            ],
          ),
          borderRadius: BorderRadius.circular(16),
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
            Text(
              'Start Creating',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: textColor,
              ),
            ),
            const SizedBox(width: 10),
            Icon(
              Icons.arrow_forward_rounded,
              size: 20,
              color: textColor,
            ),
          ],
        ),
      ),
    );
  }
}
