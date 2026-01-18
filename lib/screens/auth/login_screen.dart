import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:provider/provider.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:video_player/video_player.dart';
import '../../providers/auth_provider.dart' as app_auth;
import '../../providers/theme_provider.dart';
import '../../navigation/home_navbar.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with TickerProviderStateMixin {
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;
  late VideoPlayerController _videoController;

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();

  bool _isGoogleLoading = false;
  bool _isAppleLoading = false;
  bool _isEmailLoading = false;
  bool _isSignUpMode = false;
  bool _showVerificationScreen = false;
  bool _isVideoInitialized = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  String? _errorMessage;
  String? _successMessage;
  Timer? _verificationTimer;

  @override
  void initState() {
    super.initState();
    _setupAnimations();
    _initializeVideo();
  }

  void _setupAnimations() {
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeInOut,
    ));

    _scaleAnimation = Tween<double>(
      begin: 0.8,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _fadeController,
      curve: Curves.elasticOut,
    ));

    _fadeController.forward();
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

  Future<void> _signInWithGoogle() async {
    setState(() {
      _isGoogleLoading = true;
      _errorMessage = null;
    });

    try {
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        if (mounted) {
          setState(() => _isGoogleLoading = false);
        }
        return;
      }

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      final userCredential = await _auth.signInWithCredential(credential);
      debugPrint(
          'Google sign-in successful for uid: ${userCredential.user!.uid}');

      // Setup user profile - now properly handles errors
      if (mounted && userCredential.user != null) {
        try {
          final authProvider =
              Provider.of<app_auth.AuthProvider>(context, listen: false);
          await authProvider.setupUserProfile(userCredential.user!);
        } catch (setupError) {
          debugPrint('Profile setup failed, signing out: $setupError');
          // Sign out on setup failure so user can retry cleanly
          await _auth.signOut();
          if (mounted) {
            setState(() {
              _isGoogleLoading = false;
              _errorMessage = 'Account setup failed. Please try again.';
            });
          }
          return;  // Don't navigate to home
        }
      }

      if (mounted) {
        _navigateToHome();
      }
    } catch (e) {
      debugPrint('Google sign-in error: $e');
      if (mounted) {
        setState(() {
          _isGoogleLoading = false;
          _errorMessage = 'Google Sign-In failed. Please try again.';
        });
      }
    }
  }

  String generateNonce([int length = 32]) {
    const charset =
        '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
    final random = Random.secure();
    return List.generate(length, (_) => charset[random.nextInt(charset.length)])
        .join();
  }

  String sha256ofString(String input) {
    final bytes = utf8.encode(input);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  Future<void> _signInWithApple() async {
    if (!Platform.isIOS) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Apple Sign-In is only available on iOS devices.';
        });
      }
      return;
    }

    if (!await SignInWithApple.isAvailable()) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Apple Sign-In is not available on this device.';
        });
      }
      return;
    }

    setState(() {
      _isAppleLoading = true;
      _errorMessage = null;
    });

    try {
      final rawNonce = generateNonce();
      final nonce = sha256ofString(rawNonce);

      final appleCredential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: nonce,
      );

      if (appleCredential.identityToken == null) {
        throw Exception('Missing identity token from Apple');
      }

      final oauthCredential = OAuthProvider('apple.com').credential(
        idToken: appleCredential.identityToken!,
        rawNonce: rawNonce,
        accessToken: appleCredential.authorizationCode,
      );

      final userCredential = await _auth.signInWithCredential(oauthCredential);
      debugPrint('Apple sign-in successful for uid: ${userCredential.user!.uid}');

      // Update display name if provided
      if (appleCredential.givenName != null &&
          appleCredential.familyName != null &&
          (userCredential.user!.displayName == null ||
              userCredential.user!.displayName!.isEmpty)) {
        final displayName =
            '${appleCredential.givenName} ${appleCredential.familyName}';
        await userCredential.user!.updateDisplayName(displayName.trim());
      }

      // Setup user profile - now properly handles errors
      if (mounted && userCredential.user != null) {
        try {
          final authProvider =
              Provider.of<app_auth.AuthProvider>(context, listen: false);
          await authProvider.setupUserProfile(userCredential.user!);
        } catch (setupError) {
          debugPrint('Profile setup failed, signing out: $setupError');
          // Sign out on setup failure so user can retry cleanly
          await _auth.signOut();
          if (mounted) {
            setState(() {
              _isAppleLoading = false;
              _errorMessage = 'Account setup failed. Please try again.';
            });
          }
          return;  // Don't navigate to home
        }
      }

      if (mounted) {
        _navigateToHome();
      }
    } catch (e) {
      debugPrint('Apple Sign-In error: $e');
      if (mounted) {
        setState(() {
          _isAppleLoading = false;
          _errorMessage = 'Apple Sign-In failed. Please try again.';
        });
      }
    }
  }

  void _navigateToHome() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => const HomeNavBar()),
    );
  }

  Future<void> _signInWithEmail() async {
    if (_emailController.text.trim().isEmpty || _passwordController.text.trim().isEmpty) {
      setState(() {
        _errorMessage = 'Please enter both email and password.';
      });
      return;
    }

    setState(() {
      _isEmailLoading = true;
      _errorMessage = null;
    });

    try {
      final userCredential = await _auth.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );
      debugPrint('Email sign-in successful for uid: ${userCredential.user!.uid}');

      await userCredential.user!.reload();
      final user = _auth.currentUser!;
      if (!user.emailVerified) {
        debugPrint('Email not verified, showing verification screen');
        if (mounted) {
          setState(() {
            _isEmailLoading = false;
            _showVerificationScreen = true;
          });
          _startVerificationCheck();
        }
        return;
      }

      // Email is verified - setup user profile before navigating
      if (mounted && userCredential.user != null) {
        try {
          final authProvider =
              Provider.of<app_auth.AuthProvider>(context, listen: false);
          await authProvider.setupUserProfile(userCredential.user!);
        } catch (setupError) {
          debugPrint('Profile setup failed, signing out: $setupError');
          // Sign out on setup failure so user can retry cleanly
          await _auth.signOut();
          if (mounted) {
            setState(() {
              _isEmailLoading = false;
              _errorMessage = 'Account setup failed. Please try again.';
            });
          }
          return;  // Don't navigate to home
        }
      }

      if (mounted) {
        _navigateToHome();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isEmailLoading = false;
          _errorMessage = _getErrorMessage(e);
        });
      }
    }
  }

  Future<void> _signUpWithEmail() async {
    if (_nameController.text.trim().isEmpty) {
      setState(() {
        _errorMessage = 'Please enter your name.';
      });
      return;
    }

    if (_emailController.text.trim().isEmpty || _passwordController.text.trim().isEmpty) {
      setState(() {
        _errorMessage = 'Please enter both email and password.';
      });
      return;
    }

    if (_passwordController.text.trim().length < 6) {
      setState(() {
        _errorMessage = 'Password must be at least 6 characters long.';
      });
      return;
    }

    if (_passwordController.text.trim() != _confirmPasswordController.text.trim()) {
      setState(() {
        _errorMessage = 'Passwords do not match.';
      });
      return;
    }

    setState(() {
      _isEmailLoading = true;
      _errorMessage = null;
    });

    try {
      final userCredential = await _auth.createUserWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      await userCredential.user!.updateDisplayName(_nameController.text.trim());
      debugPrint('Email sign-up successful for uid: ${userCredential.user!.uid}');

      await userCredential.user!.sendEmailVerification();
      debugPrint('Verification email sent to: ${userCredential.user!.email}');

      if (mounted) {
        setState(() {
          _isEmailLoading = false;
          _showVerificationScreen = true;
          _successMessage = 'Account created! Please check your email for verification.';
        });
        _startVerificationCheck();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isEmailLoading = false;
          _errorMessage = _getErrorMessage(e);
        });
      }
    }
  }

  void _startVerificationCheck() {
    _verificationTimer = Timer.periodic(const Duration(seconds: 3), (timer) async {
      await _auth.currentUser?.reload();
      final user = _auth.currentUser;
      if (user != null && user.emailVerified) {
        timer.cancel();
        debugPrint('Email verified! Proceeding to home.');

        // Setup user profile - now properly handles errors
        if (mounted) {
          try {
            final authProvider =
                Provider.of<app_auth.AuthProvider>(context, listen: false);
            await authProvider.setupUserProfile(user);

            setState(() {
              _successMessage = 'Email verified successfully!';
            });
            await Future.delayed(const Duration(seconds: 1));
            _navigateToHome();
          } catch (setupError) {
            debugPrint('Profile setup failed after verification: $setupError');
            if (mounted) {
              setState(() {
                _errorMessage = 'Account setup failed. Please try signing in again.';
              });
              // Sign out so they can retry
              await _auth.signOut();
            }
          }
        }
      }
    });
  }

  Future<void> _resendVerificationEmail() async {
    try {
      await _auth.currentUser?.sendEmailVerification();
      if (mounted) {
        setState(() {
          _successMessage = 'Verification email sent! Please check your inbox.';
          _errorMessage = null;
        });
      }
      debugPrint('Verification email resent');
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to send verification email: ${_getErrorMessage(e)}';
          _successMessage = null;
        });
      }
    }
  }

  Future<void> _showForgotPasswordDialog() async {
    final emailController = TextEditingController(text: _emailController.text);
    final theme = Theme.of(context);

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset Password'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Enter your email address and we\'ll send you a link to reset your password.',
              style: TextStyle(
                color: theme.colorScheme.onSurfaceVariant,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(
                hintText: 'Email address',
                prefixIcon: const Icon(Icons.email_outlined),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              'Cancel',
              style: TextStyle(color: theme.colorScheme.outline),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Send Reset Link'),
          ),
        ],
      ),
    );

    if (result == true && emailController.text.trim().isNotEmpty) {
      await _sendPasswordResetEmail(emailController.text.trim());
    }

    emailController.dispose();
  }

  Future<void> _sendPasswordResetEmail(String email) async {
    setState(() {
      _isEmailLoading = true;
      _errorMessage = null;
      _successMessage = null;
    });

    try {
      await _auth.sendPasswordResetEmail(email: email);
      if (mounted) {
        setState(() {
          _isEmailLoading = false;
          _successMessage = 'Password reset email sent! Please check your inbox.';
        });
      }
      debugPrint('Password reset email sent to: $email');
    } catch (e) {
      if (mounted) {
        setState(() {
          _isEmailLoading = false;
          _errorMessage = _getErrorMessage(e);
        });
      }
    }
  }

  void _signOut() async {
    await _auth.signOut();
    if (mounted) {
      setState(() {
        _showVerificationScreen = false;
        _errorMessage = null;
        _successMessage = null;
      });
    }
    _verificationTimer?.cancel();
  }

  String _getErrorMessage(dynamic error) {
    if (error is FirebaseAuthException) {
      switch (error.code) {
        case 'weak-password':
          return 'The password provided is too weak.';
        case 'email-already-in-use':
          return 'An account already exists for this email.';
        case 'invalid-email':
          return 'Please enter a valid email address.';
        case 'user-not-found':
          return 'No user found for this email.';
        case 'wrong-password':
          return 'Wrong password provided.';
        case 'user-disabled':
          return 'This user account has been disabled.';
        case 'too-many-requests':
          return 'Too many attempts. Please try again later.';
        default:
          return 'Authentication failed: ${error.message}';
      }
    }
    return 'An error occurred. Please try again.';
  }

  void _toggleAuthMode() {
    setState(() {
      _isSignUpMode = !_isSignUpMode;
      _errorMessage = null;
      _successMessage = null;
      _emailController.clear();
      _passwordController.clear();
      _confirmPasswordController.clear();
      _nameController.clear();
      _obscurePassword = true;
      _obscureConfirmPassword = true;
    });
  }

  Widget _buildGlassButton({
    required VoidCallback? onPressed,
    required Widget child,
    bool isLoading = false,
    double height = 48,
    bool isPrimary = false,
  }) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final accentColor = themeProvider.accentColor;

    return Container(
      width: double.infinity,
      height: height,
      decoration: BoxDecoration(
        color: isPrimary
            ? accentColor.withValues(alpha: 0.9)
            : Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isPrimary
              ? accentColor
              : Colors.white.withValues(alpha: 0.3),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: isLoading ? null : onPressed,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            alignment: Alignment.center,
            child: isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      strokeWidth: 2.5,
                    ),
                  )
                : child,
          ),
        ),
      ),
    );
  }

  Widget _buildInputField({
    required TextEditingController controller,
    required String hintText,
    required IconData icon,
    bool obscureText = false,
    TextInputType keyboardType = TextInputType.text,
    VoidCallback? onToggleObscure,
    bool? isObscured,
  }) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final accentColor = themeProvider.accentColor;

    return SizedBox(
      height: 52,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: accentColor.withValues(alpha: 0.5),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: TextField(
          controller: controller,
          cursorColor: accentColor,
          style: TextStyle(
            color: accentColor,
            fontSize: 15,
            fontWeight: FontWeight.w500,
          ),
          keyboardType: keyboardType,
          obscureText: obscureText,
          decoration: InputDecoration(
            hintText: hintText,
            hintStyle: TextStyle(
              color: accentColor.withValues(alpha: 0.9),
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
            prefixIcon: Icon(
              icon,
              color: accentColor,
              size: 20,
            ),
            suffixIcon: onToggleObscure != null
                ? IconButton(
                    icon: Icon(
                      isObscured! ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                      color: accentColor,
                      size: 20,
                    ),
                    onPressed: onToggleObscure,
                  )
                : null,
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 14,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildVerificationScreen() {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final textPrimary = themeProvider.textPrimaryColor;
    final textSecondary = themeProvider.textSecondaryColor;
    final accentColor = themeProvider.accentColor;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 100,
          height: 100,
          decoration: BoxDecoration(
            color: accentColor.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.mark_email_read_outlined,
            size: 50,
            color: accentColor,
          ),
        ),
        const SizedBox(height: 32),
        Text(
          'Verify Your Email',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w600,
            color: textPrimary,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text(
            'We\'ve sent a verification link to:\n${_auth.currentUser?.email ?? ''}',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              color: textSecondary,
              height: 1.5,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Please check your email and click the verification link.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            color: textSecondary.withValues(alpha: 0.8),
          ),
        ),
        const SizedBox(height: 32),
        _buildGlassButton(
          onPressed: _resendVerificationEmail,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.refresh, color: textPrimary, size: 18),
              const SizedBox(width: 10),
              Text(
                'Resend Verification Email',
                style: TextStyle(
                  color: textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _buildGlassButton(
          onPressed: _signOut,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.logout, color: textPrimary, size: 18),
              const SizedBox(width: 10),
              Text(
                'Sign Out',
                style: TextStyle(
                  color: textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(accentColor),
                strokeWidth: 2,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              'Checking verification status...',
              style: TextStyle(
                color: textSecondary,
                fontSize: 13,
              ),
            ),
          ],
        ),
        if (_successMessage != null) ...[
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.green.withValues(alpha: 0.1),
                  Colors.green.withValues(alpha: 0.05),
                ],
              ),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: Colors.green.withValues(alpha: 0.3),
                width: 1,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.check_circle_outline,
                  color: Colors.green.withValues(alpha: 0.8),
                  size: 18,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _successMessage!,
                    style: TextStyle(
                      color: Colors.green.withValues(alpha: 0.9),
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        if (_errorMessage != null) ...[
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.red.withValues(alpha: 0.1),
                  Colors.red.withValues(alpha: 0.05),
                ],
              ),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: Colors.red.withValues(alpha: 0.3),
                width: 1,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.error_outline,
                  color: Colors.red.withValues(alpha: 0.8),
                  size: 18,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _errorMessage!,
                    style: TextStyle(
                      color: Colors.red.withValues(alpha: 0.9),
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _videoController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _nameController.dispose();
    _verificationTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final accentColor = themeProvider.accentColor;
    final isDark = themeProvider.isDarkTheme;
    final theme = themeProvider.currentThemeColors;

    // Verification screen
    if (_showVerificationScreen) {
      return Scaffold(
        body: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: isDark
                  ? [theme['background']!, theme['primary']!]
                  : [theme['background']!, theme['background']!],
            ),
          ),
          child: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 40.0),
                child: _buildVerificationScreen(),
              ),
            ),
          ),
        ),
      );
    }

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

          // Auth UI on top
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 24.0),
              child: AnimatedBuilder(
                animation: _fadeController,
                builder: (context, child) {
                  return FadeTransition(
                    opacity: _fadeAnimation,
                    child: ScaleTransition(
                      scale: _scaleAnimation,
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          return SingleChildScrollView(
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                minHeight: constraints.maxHeight,
                              ),
                              child: IntrinsicHeight(
                                child: Column(
                        children: [
                          const SizedBox(height: 60),

                          // App Title
                          Text(
                            'Outfiti',
                            style: TextStyle(
                              fontSize: 36,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                              letterSpacing: -0.5,
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
                          const SizedBox(height: 10),

                          // Subtitle
                          Text(
                            'Transform Your Look with AI',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 15,
                              color: Colors.white.withValues(alpha: 0.9),
                              fontWeight: FontWeight.w400,
                              height: 1.5,
                              shadows: [
                                Shadow(
                                  color: Colors.black.withValues(alpha: 0.5),
                                  offset: const Offset(0, 1),
                                  blurRadius: 4,
                                ),
                              ],
                            ),
                          ),

                          // Push content to middle of screen
                          SizedBox(height: constraints.maxHeight * 0.22),

                        // Middle section: Auth fields and buttons
                        Column(
                          children: [

                            // Email/Password Fields
                            if (_isSignUpMode) ...[
                              _buildInputField(
                                controller: _nameController,
                                hintText: 'Full Name',
                                icon: Icons.person_outline,
                              ),
                              const SizedBox(height: 12),
                            ],
                            _buildInputField(
                              controller: _emailController,
                              hintText: 'Email Address',
                              icon: Icons.email_outlined,
                              keyboardType: TextInputType.emailAddress,
                            ),
                            const SizedBox(height: 12),
                            _buildInputField(
                              controller: _passwordController,
                              hintText: 'Password',
                              icon: Icons.lock_outline,
                              obscureText: _obscurePassword,
                              onToggleObscure: () {
                                setState(() {
                                  _obscurePassword = !_obscurePassword;
                                });
                              },
                              isObscured: _obscurePassword,
                            ),
                            // Forgot Password link (only in sign-in mode)
                            if (!_isSignUpMode) ...[
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton(
                                  onPressed: _showForgotPasswordDialog,
                                  style: TextButton.styleFrom(
                                    minimumSize: Size.zero,
                                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  child: Text(
                                    'Forgot Password?',
                                    style: TextStyle(
                                      color: accentColor,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                            ],
                            if (_isSignUpMode) ...[
                              const SizedBox(height: 12),
                              _buildInputField(
                                controller: _confirmPasswordController,
                                hintText: 'Confirm Password',
                                icon: Icons.lock_outline,
                                obscureText: _obscureConfirmPassword,
                                onToggleObscure: () {
                                  setState(() {
                                    _obscureConfirmPassword = !_obscureConfirmPassword;
                                  });
                                },
                                isObscured: _obscureConfirmPassword,
                              ),
                              const SizedBox(height: 20),
                            ],

                          // Email Sign-in/Sign-up Button
                          _buildGlassButton(
                            onPressed: _isEmailLoading
                                ? null
                                : (_isSignUpMode ? _signUpWithEmail : _signInWithEmail),
                            isLoading: _isEmailLoading,
                            isPrimary: true,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.email_outlined, color: Colors.white, size: 18),
                                const SizedBox(width: 10),
                                Text(
                                  _isSignUpMode ? 'Create Account' : 'Sign In',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 0.3,
                                  ),
                                ),
                              ],
                            ),
                          ),

                            const SizedBox(height: 12),

                            // Toggle Sign Up / Sign In
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  _isSignUpMode
                                      ? 'Already have an account?'
                                      : 'Don\'t have an account?',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.8),
                                    fontSize: 12,
                                  ),
                                ),
                                TextButton(
                                  onPressed: _toggleAuthMode,
                                  style: TextButton.styleFrom(
                                    minimumSize: Size.zero,
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  child: Text(
                                    _isSignUpMode ? 'Sign In' : 'Sign Up',
                                    style: TextStyle(
                                      color: accentColor,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 18),

                            // Divider
                            Row(
                              children: [
                                Expanded(
                                  child: Container(
                                    height: 1,
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: [
                                          Colors.transparent,
                                          Colors.white.withValues(alpha: 0.3),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 12),
                                  child: Text(
                                    'or continue with',
                                    style: TextStyle(
                                      color: Colors.white.withValues(alpha: 0.6),
                                      fontSize: 11,
                                      fontWeight: FontWeight.w400,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: Container(
                                    height: 1,
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: [
                                          Colors.white.withValues(alpha: 0.3),
                                          Colors.transparent,
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 14),

                          // Google Sign-in Button
                          _buildGlassButton(
                            onPressed: _signInWithGoogle,
                            isLoading: _isGoogleLoading,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                SvgPicture.asset(
                                  'assets/icons/google.svg',
                                  width: 18,
                                  height: 18,
                                ),
                                const SizedBox(width: 10),
                                const Text(
                                  'Continue with Google',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    letterSpacing: 0.2,
                                  ),
                                ),
                              ],
                            ),
                          ),

                          // Apple Sign-in Button (iOS only)
                          if (Platform.isIOS) ...[
                            const SizedBox(height: 12),
                            _buildGlassButton(
                              onPressed: _signInWithApple,
                              isLoading: _isAppleLoading,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  SvgPicture.asset(
                                    'assets/icons/apple.svg',
                                    width: 18,
                                    height: 18,
                                    colorFilter: const ColorFilter.mode(
                                      Colors.white,
                                      BlendMode.srcIn,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  const Text(
                                    'Continue with Apple',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                      letterSpacing: 0.2,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],

                            // Error Message
                            if (_errorMessage != null) ...[
                              const SizedBox(height: 16),
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                      Colors.red.withValues(alpha: 0.1),
                                      Colors.red.withValues(alpha: 0.05),
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: Colors.red.withValues(alpha: 0.3),
                                    width: 1,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.error_outline,
                                      color: Colors.red.withValues(alpha: 0.8),
                                      size: 16,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        _errorMessage!,
                                        style: TextStyle(
                                          color: Colors.red.withValues(alpha: 0.9),
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),

                          const SizedBox(height: 24),

                          // Bottom section: Privacy notice
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Text(
                              'By continuing, you agree to our Terms of Service and Privacy Policy',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.white.withValues(alpha: 0.6),
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
