import 'dart:async';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'firebase_options.dart';
import 'providers/auth_provider.dart' as app_auth;
import 'providers/gallery_refresh_notifier.dart';
import 'providers/outfit_tryon_provider.dart';
import 'providers/theme_provider.dart';
import 'navigation/home_navbar.dart';
import 'screens/auth/login_screen.dart';
import 'screens/onboarding/onboarding_flow.dart';
import 'services/outfit_service.dart';
import 'services/credit_service.dart';
import 'services/review_prompt_service.dart';
import 'services/onboarding_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Initialize Firebase App Check for security
  await FirebaseAppCheck.instance.activate(
    // iOS: Use DeviceCheck for debug, App Attest for production
    appleProvider: kDebugMode
        ? AppleProvider.debug
        : AppleProvider.appAttest,
    // Android: Use Debug provider for debug, Play Integrity for production
    androidProvider: kDebugMode
        ? AndroidProvider.debug
        : AndroidProvider.playIntegrity,
    // Web support (optional)
    webProvider: ReCaptchaV3Provider('recaptcha-v3-site-key'),
  );

  final themeProvider = ThemeProvider();
  await themeProvider.initializeTheme();

  // Initialize ReviewPromptService
  final creditService = CreditService();
  final reviewPromptService = ReviewPromptService(creditService);
  await reviewPromptService.initialize();

  runApp(OutfitiApp(
    themeProvider: themeProvider,
    reviewPromptService: reviewPromptService,
  ));
}

class OutfitiApp extends StatelessWidget {
  final ThemeProvider themeProvider;
  final ReviewPromptService reviewPromptService;

  const OutfitiApp({
    super.key,
    required this.themeProvider,
    required this.reviewPromptService,
  });

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: themeProvider),
        ChangeNotifierProvider(create: (_) => app_auth.AuthProvider()),
        ChangeNotifierProvider(
          create: (_) => OutfitTryOnProvider(MockOutfitService()),
        ),
        ChangeNotifierProvider(create: (_) => GalleryRefreshNotifier()),
        Provider.value(value: reviewPromptService),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, _) {
          return MaterialApp(
            title: 'Outfiti',
            debugShowCheckedModeBanner: false,
            theme: themeProvider.currentTheme,
            home: const AuthWrapper(),
          );
        },
      ),
    );
  }
}

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  final OnboardingService _onboardingService = OnboardingService();

  /// Checks if user profile exists and has required fields.
  /// If not, attempts to recover by calling setupUserProfile.
  /// This handles users who authenticated but failed profile creation.
  Future<void> _checkAndRecoverProfile(User user) async {
    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users').doc(user.uid).get();

      // Check if doc is missing or incomplete (no credits field)
      if (!userDoc.exists || userDoc.data()?['credits'] == null) {
        debugPrint('Recovery: User ${user.uid} has incomplete profile, attempting recovery...');

        // Attempt to recover by re-running setup
        final authProvider = Provider.of<app_auth.AuthProvider>(context, listen: false);
        await authProvider.setupUserProfile(user);

        debugPrint('Recovery: Successfully recovered profile for ${user.uid}');
      }
    } catch (e) {
      // Log but don't block - the server-side backfill can recover this
      debugPrint('Recovery: Failed to recover profile for ${user.uid}: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(),
            ),
          );
        }

        if (snapshot.hasData && snapshot.data != null) {
          final user = snapshot.data!;

          // Check if this is an OAuth user (Google/Apple) - they don't need email verification
          final isOAuthUser = user.providerData.any((info) =>
            info.providerId == 'google.com' || info.providerId == 'apple.com'
          );

          // For email/password users, check if email is verified
          if (!isOAuthUser && !user.emailVerified) {
            // Show verification pending screen instead of signing out
            return const EmailVerificationScreen();
          }

          // Check and recover incomplete profiles, then check onboarding status
          return FutureBuilder<void>(
            // First attempt profile recovery for users with incomplete profiles
            future: _checkAndRecoverProfile(user),
            builder: (context, recoverySnapshot) {
              if (recoverySnapshot.connectionState == ConnectionState.waiting) {
                return const Scaffold(
                  body: Center(
                    child: CircularProgressIndicator(),
                  ),
                );
              }

              // Then check onboarding status
              return FutureBuilder<bool>(
                future: _onboardingService.hasCompletedOnboarding(),
                builder: (context, onboardingSnapshot) {
                  if (onboardingSnapshot.connectionState == ConnectionState.waiting) {
                    return const Scaffold(
                      body: Center(
                        child: CircularProgressIndicator(),
                      ),
                    );
                  }

                  final hasCompletedOnboarding = onboardingSnapshot.data ?? false;

                  if (!hasCompletedOnboarding) {
                    return const OnboardingFlow();
                  }

                  return const HomeNavBar();
                },
              );
            },
          );
        }

        return const LoginScreen();
      },
    );
  }
}

/// Screen shown when user needs to verify their email
class EmailVerificationScreen extends StatefulWidget {
  const EmailVerificationScreen({super.key});

  @override
  State<EmailVerificationScreen> createState() => _EmailVerificationScreenState();
}

class _EmailVerificationScreenState extends State<EmailVerificationScreen> {
  Timer? _verificationTimer;
  bool _isResending = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _startVerificationCheck();
  }

  @override
  void dispose() {
    _verificationTimer?.cancel();
    super.dispose();
  }

  void _startVerificationCheck() {
    _verificationTimer = Timer.periodic(const Duration(seconds: 3), (timer) async {
      final user = FirebaseAuth.instance.currentUser;
      await user?.reload();
      if (user != null && user.emailVerified) {
        timer.cancel();
        // Setup user profile now that email is verified - with error handling
        if (mounted) {
          try {
            final authProvider = Provider.of<app_auth.AuthProvider>(context, listen: false);
            await authProvider.setupUserProfile(user);

            // Navigate to home - StreamBuilder won't detect emailVerified change
            if (mounted) {
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (context) => const HomeNavBar()),
                (route) => false,
              );
            }
          } catch (e) {
            debugPrint('Profile setup failed after email verification: $e');
            // The recovery check will handle this on next app launch
            // Still navigate to home - server-side functions will create the profile
            if (mounted) {
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (context) => const HomeNavBar()),
                (route) => false,
              );
            }
          }
        }
      }
    });
  }

  Future<void> _resendVerificationEmail() async {
    setState(() {
      _isResending = true;
      _message = null;
    });

    try {
      await FirebaseAuth.instance.currentUser?.sendEmailVerification();
      if (mounted) {
        setState(() {
          _isResending = false;
          _message = 'Verification email sent!';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isResending = false;
          _message = 'Failed to send email. Please try again.';
        });
      }
    }
  }

  Future<void> _signOut() async {
    _verificationTimer?.cancel();
    await FirebaseAuth.instance.signOut();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final user = FirebaseAuth.instance.currentUser;
    final accentColor = theme.colorScheme.secondary;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.mark_email_unread_outlined,
                size: 80,
                color: accentColor,
              ),
              const SizedBox(height: 24),
              Text(
                'Verify Your Email',
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'We sent a verification link to:',
                style: theme.textTheme.bodyLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                user?.email ?? '',
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: accentColor,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              Text(
                'Please check your inbox and click the verification link to continue.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.outline,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              // Waiting indicator
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: accentColor,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Waiting for verification...',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.outline,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              if (_message != null) ...[
                Text(
                  _message!,
                  style: TextStyle(
                    color: _message!.contains('sent')
                        ? Colors.green
                        : Colors.red,
                  ),
                ),
                const SizedBox(height: 16),
              ],
              FilledButton.icon(
                onPressed: _isResending ? null : _resendVerificationEmail,
                icon: _isResending
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh),
                label: Text(_isResending ? 'Sending...' : 'Resend Email'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _signOut,
                icon: Icon(Icons.arrow_back, color: accentColor),
                label: Text(
                  'Back to Login',
                  style: TextStyle(color: accentColor),
                ),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                  side: BorderSide(color: accentColor.withValues(alpha: 0.5)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
