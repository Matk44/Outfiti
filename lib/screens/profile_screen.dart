import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../providers/theme_provider.dart';
import '../providers/auth_provider.dart' as app_auth;
import '../services/user_profile_service.dart';
import '../services/credit_service.dart';
import '../widgets/profile_image_picker.dart';
import '../widgets/paywall_modal.dart';
import '../widgets/credit_topup_modal.dart';
import 'feedback_screen.dart';

/// Profile screen - User profile and app settings
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final UserProfileService _profileService = UserProfileService();
  final CreditService _creditService = CreditService();
  final TextEditingController _nameController = TextEditingController();
  bool _isEditingName = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _updateDisplayName() async {
    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Name cannot be empty'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    try {
      await _profileService.updateDisplayName(_nameController.text.trim());
      if (mounted) {
        setState(() {
          _isEditingName = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Name updated successfully'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error updating name: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _deleteAccountWithConfirmation() async {
    final theme = Theme.of(context);

    // First confirmation dialog
    final firstConfirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: SvgPicture.asset(
          'assets/icons/warning.svg',
          width: 48,
          height: 48,
          colorFilter: const ColorFilter.mode(Colors.red, BlendMode.srcIn),
        ),
        title: const Text('Delete Account?'),
        content: const Text(
          'This will permanently delete your account and all associated data including:\n\n'
          '• Your profile information\n'
          '• All saved hairstyle images\n'
          '• Your credit balance\n'
          '• All app settings\n\n'
          'This action cannot be undone. Are you sure you want to continue?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              'Cancel',
              style: TextStyle(
                color: theme.colorScheme.secondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('Continue'),
          ),
        ],
      ),
    );

    if (firstConfirm != true) return;

    // Check if widget is still mounted before showing second dialog
    if (!mounted) return;

    // Second confirmation dialog
    final secondConfirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: SvgPicture.asset(
          'assets/icons/trash.svg',
          width: 48,
          height: 48,
          colorFilter: const ColorFilter.mode(Colors.red, BlendMode.srcIn),
        ),
        title: const Text('Final Confirmation'),
        content: const Text(
          'This is your last chance to cancel.\n\n'
          'Once deleted, your account and all data will be permanently removed '
          'and cannot be recovered.\n\n'
          'Do you want to proceed with account deletion?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              'Cancel',
              style: TextStyle(
                color: theme.colorScheme.secondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('Delete Account'),
          ),
        ],
      ),
    );

    if (secondConfirm != true) return;

    // Show loading dialog
    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: Card(
            child: Padding(
              padding: EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Deleting account...'),
                ],
              ),
            ),
          ),
        ),
      );
    }

    // Perform account deletion
    try {
      await _deleteUserAccountAndData();

      if (mounted) {
        Navigator.pop(context); // Close loading dialog
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Account deleted successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Close loading dialog
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error deleting account: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  Future<void> _deleteUserAccountAndData() async {
    final authProvider = Provider.of<app_auth.AuthProvider>(
      context,
      listen: false,
    );
    final userId = authProvider.user?.uid;

    if (userId == null) {
      throw Exception('No user logged in');
    }

    // Delete user data from Firestore
    final firestore = FirebaseFirestore.instance;

    // Delete user profile document
    await firestore.collection('users').doc(userId).delete();

    // Delete user credits document
    await firestore.collection('userCredits').doc(userId).delete();

    // Delete user gallery images from Firestore (if you have a collection for that)
    // Note: This deletes the Firestore documents, not the Storage files
    final gallerySnapshot = await firestore
        .collection('users')
        .doc(userId)
        .collection('gallery')
        .get();

    for (var doc in gallerySnapshot.docs) {
      await doc.reference.delete();
    }

    // Delete any other user-related collections here
    // Example: saved hairstyles, favorites, etc.

    // Delete Firebase Authentication account
    // This will automatically sign out the user
    await authProvider.deleteAccount();
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile & Settings'),
      ),
      body: Builder(
        builder: (context) {
          final stream = _profileService.getUserProfileStream();
          if (stream == null) {
            // No user logged in, show empty state
            return const Center(child: Text('Please sign in'));
          }

          return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: stream,
            builder: (context, snapshot) {
              final profileData = snapshot.data?.data();
              final displayName = profileData?['displayName'] ?? '';
              final profileImageUrl = profileData?['profileImageUrl'] ?? '';
              final scale = (profileData?['profileImageScale'] as num?)?.toDouble() ?? 1.0;
              final offsetX = (profileData?['profileImageOffsetX'] as num?)?.toDouble() ?? 0.0;
              final offsetY = (profileData?['profileImageOffsetY'] as num?)?.toDouble() ?? 0.0;

          // Update controller only if not editing and name changed
          if (!_isEditingName && _nameController.text != displayName) {
            _nameController.text = displayName;
          }

          return ListView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 100),
            children: [
              // Profile Section
              Column(
                children: [
                  // Profile Avatar
                  ProfileImagePicker(
                    currentImageUrl: profileImageUrl,
                    size: 120,
                    showEditButton: true,
                    initialScale: scale,
                    initialOffsetX: offsetX,
                    initialOffsetY: offsetY,
                    onImageUploaded: (url) {
                      // Profile updates automatically via stream
                    },
                  ),
                  const SizedBox(height: 24),

                  // Name Field
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: themeProvider.textSecondaryColor.withValues(alpha: 0.3),
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Name',
                              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                                    color: themeProvider.textSecondaryColor,
                                  ),
                            ),
                            if (!_isEditingName)
                              IconButton(
                                icon: Icon(
                                  Icons.edit,
                                  color: themeProvider.accentColor,
                                  size: 20,
                                ),
                                onPressed: () {
                                  setState(() {
                                    _isEditingName = true;
                                  });
                                },
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        if (_isEditingName)
                          Column(
                            children: [
                              TextField(
                                controller: _nameController,
                                decoration: InputDecoration(
                                  hintText: 'Enter your name',
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),
                                ),
                                autofocus: true,
                              ),
                              const SizedBox(height: 12),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  TextButton(
                                    onPressed: () {
                                      setState(() {
                                        _isEditingName = false;
                                        _nameController.text = displayName;
                                      });
                                    },
                                    child: const Text('Cancel'),
                                  ),
                                  const SizedBox(width: 8),
                                  FilledButton(
                                    onPressed: _updateDisplayName,
                                    child: const Text('Save'),
                                  ),
                                ],
                              ),
                            ],
                          )
                        else
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                displayName.isEmpty ? 'Not set' : displayName,
                                style: Theme.of(context).textTheme.bodyLarge,
                              ),
                              // Premium badge for pro users
                              StreamBuilder<UserCredits>(
                                stream: _creditService.creditsStream,
                                builder: (context, snapshot) {
                                  final plan = snapshot.data?.plan ?? UserPlan.free;
                                  final isPro = plan == UserPlan.monthlyPro || plan == UserPlan.annualPro;

                                  if (!isPro) return const SizedBox.shrink();

                                  return Padding(
                                    padding: const EdgeInsets.only(top: 8),
                                    child: Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                          decoration: BoxDecoration(
                                            gradient: LinearGradient(
                                              begin: Alignment.topLeft,
                                              end: Alignment.bottomRight,
                                              colors: [
                                                themeProvider.accentColor,
                                                themeProvider.accentColor.withValues(alpha: 0.8),
                                              ],
                                            ),
                                            borderRadius: BorderRadius.circular(20),
                                            boxShadow: [
                                              BoxShadow(
                                                color: themeProvider.accentColor.withValues(alpha: 0.3),
                                                blurRadius: 8,
                                                offset: const Offset(0, 2),
                                              ),
                                            ],
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              SvgPicture.asset(
                                                'assets/icons/premium.svg',
                                                width: 16,
                                                height: 16,
                                                colorFilter: ColorFilter.mode(
                                                  ThemeData.estimateBrightnessForColor(themeProvider.accentColor) ==
                                                          Brightness.light
                                                      ? Colors.black
                                                      : Colors.white,
                                                  BlendMode.srcIn,
                                                ),
                                              ),
                                              const SizedBox(width: 6),
                                              Text(
                                                plan == UserPlan.monthlyPro ? 'PRO MONTHLY' : 'PRO ANNUAL',
                                                style: GoogleFonts.plusJakartaSans(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w700,
                                                  letterSpacing: 0.5,
                                                  color: ThemeData.estimateBrightnessForColor(themeProvider.accentColor) ==
                                                          Brightness.light
                                                      ? Colors.black
                                                      : Colors.white,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),
              const Divider(),
              const SizedBox(height: 24),

              // Style Credits Section
              _buildStyleCreditsSection(context, themeProvider),
              const SizedBox(height: 32),
              const Divider(),
              const SizedBox(height: 24),

              // Theme Selection Section
              Text(
                'Theme Selection',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: themeProvider.textSecondaryColor.withValues(alpha: 0.3),
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: DropdownButton<String>(
                  value: themeProvider.selectedTheme,
                  isExpanded: true,
                  underline: const SizedBox(),
                  icon: const Icon(Icons.keyboard_arrow_down),
                  items: themeProvider.availableThemes.map((themeName) {
                    final themeColors = _getThemePreviewColors(themeName);
                    return DropdownMenuItem<String>(
                      value: themeName,
                      child: Row(
                        children: [
                          // Color preview
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: themeColors['background'],
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: themeProvider.textSecondaryColor.withValues(alpha: 0.2),
                              ),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: themeColors['primary'],
                                      borderRadius: const BorderRadius.only(
                                        topLeft: Radius.circular(5),
                                        bottomLeft: Radius.circular(5),
                                      ),
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: themeColors['accent'],
                                      borderRadius: const BorderRadius.only(
                                        topRight: Radius.circular(5),
                                        bottomRight: Radius.circular(5),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(themeName),
                        ],
                      ),
                    );
                  }).toList(),
                  onChanged: (String? newTheme) {
                    if (newTheme != null) {
                      themeProvider.setTheme(newTheme);
                    }
                  },
                ),
              ),
              const SizedBox(height: 32),
              const Divider(),
              const SizedBox(height: 24),

              // Support/Feedback Section
              Text(
                'Support/Feedback',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: themeProvider.textSecondaryColor.withValues(alpha: 0.3),
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Submit Feedback or Report Issue',
                            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                  fontWeight: FontWeight.w500,
                                ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Help us improve the app',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    FilledButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const FeedbackScreen(),
                          ),
                        );
                      },
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.feedback_outlined, size: 18),
                          SizedBox(width: 6),
                          Text('Submit'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              const Divider(),
              const SizedBox(height: 16),

              // Account Section
              Text(
                'Account',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 16),

              // Danger Zone Section
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.05),
                  border: Border.all(
                    color: Colors.red.withValues(alpha: 0.3),
                    width: 1.5,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              SvgPicture.asset(
                                'assets/icons/warning.svg',
                                width: 18,
                                height: 18,
                                colorFilter: const ColorFilter.mode(Colors.red, BlendMode.srcIn),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Danger Zone',
                                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                      color: Colors.red,
                                      fontWeight: FontWeight.w500,
                                    ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Permanently delete account',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: Colors.red.withValues(alpha: 0.7),
                                ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    FilledButton(
                      onPressed: _deleteAccountWithConfirmation,
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.red,
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SvgPicture.asset(
                            'assets/icons/trash.svg',
                            width: 18,
                            height: 18,
                            colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
                          ),
                          const SizedBox(width: 6),
                          const Text('Delete'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              FilledButton.tonal(
                onPressed: () async {
                  final authProvider = Provider.of<app_auth.AuthProvider>(
                    context,
                    listen: false,
                  );
                  await authProvider.signOut();
                },
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(56),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.logout),
                    SizedBox(width: 8),
                    Text('Sign Out'),
                  ],
                ),
              ),
            ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildStyleCreditsSection(BuildContext context, ThemeProvider themeProvider) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Style Credits',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 16),
        StreamBuilder<UserCredits>(
          stream: _creditService.creditsStream,
          builder: (context, snapshot) {
            final credits = snapshot.data?.credits ?? 0;
            final plan = snapshot.data?.plan ?? UserPlan.free;
            final isPro = plan == UserPlan.monthlyPro || plan == UserPlan.annualPro;

            // Determine color based on credit level (matching ProfileCircleButton)
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

            return Column(
              children: [
                // Credits display container (similar to ProfileCircleButton style)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  decoration: BoxDecoration(
                    color: themeProvider.surfaceColor,
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(
                      color: borderColor,
                      width: 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: creditColor.withValues(alpha: 0.15),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      // Animated credits GIF
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: creditColor,
                            width: 2,
                          ),
                        ),
                        child: ClipOval(
                          child: Image.asset(
                            'assets/icons/credits.gif',
                            width: 56,
                            height: 56,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      // Credits info
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'STYLE CREDITS',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: creditColor,
                                letterSpacing: 1.0,
                              ),
                            ),
                            const SizedBox(height: 4),
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
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 32,
                                  fontWeight: FontWeight.bold,
                                  color: creditColor,
                                  height: 1.0,
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '1 credit = 1 AI try-on',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 12,
                                color: themeProvider.textSecondaryColor.withValues(alpha: 0.7),
                              ),
                            ),
                            // Show max credit cap for pro users
                            if (isPro)
                              Text(
                                'Max credits you can hold: 100',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 12,
                                  color: themeProvider.textSecondaryColor.withValues(alpha: 0.7),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                // Conditional Add Credits button
                // Free users: Show button to upgrade to Pro
                // Pro users with <10 credits: Show button to top-up credits
                // Pro users with >=10 credits: Hide button
                if (!isPro || (isPro && credits < 10))
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () {
                        if (isPro) {
                          // Pro users: Navigate to credit top-up modal
                          CreditTopUpModal.show(context);
                        } else {
                          // Free users: Navigate to paywall to upgrade
                          PaywallModal.show(context);
                        }
                      },
                      borderRadius: BorderRadius.circular(28),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              creditColor,
                              creditColor.withValues(alpha: 0.8),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(28),
                          boxShadow: [
                            BoxShadow(
                              color: creditColor.withValues(alpha: 0.3),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 24,
                              height: 24,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white.withValues(alpha: 0.2),
                              ),
                              child: Icon(
                                Icons.add,
                                size: 16,
                                color: ThemeData.estimateBrightnessForColor(creditColor) ==
                                        Brightness.light
                                    ? Colors.black
                                    : Colors.white,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              'Add Style Credits',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: ThemeData.estimateBrightnessForColor(creditColor) ==
                                        Brightness.light
                                    ? Colors.black
                                    : Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  Map<String, Color> _getThemePreviewColors(String themeName) {
    switch (themeName) {
      case 'Divine Gold':
        return {
          'primary': const Color(0xFFFFFFFF),
          'accent': const Color(0xFFC5A059),
          'background': const Color(0xFFFFFCF9),
        };
      case 'Peaches & Cream':
        return {
          'primary': const Color(0xFFE8E4E1),
          'accent': const Color(0xFFFF8E72),
          'background': const Color(0xFFF5F3F0),
        };
      case 'Midnight Purple':
        return {
          'primary': const Color(0xFF2C1A47),
          'accent': const Color(0xFFFFD700),
          'background': const Color(0xFF1A1127),
        };
      case 'Forest Whisper':
        return {
          'primary': const Color(0xFF2C472C),
          'accent': const Color(0xFF98FB98),
          'background': const Color(0xFF1A271A),
        };
      case 'Sunset Glow':
        return {
          'primary': const Color(0xFF473C1A),
          'accent': const Color(0xFFFFA500),
          'background': const Color(0xFF272111),
        };
      case 'Twilight Rose':
        return {
          'primary': const Color(0xFF4A2C47),
          'accent': const Color(0xFFFF69B4),
          'background': const Color(0xFF271A25),
        };
      case 'Obsidian Night':
        return {
          'primary': const Color(0xFF1A1A1A),
          'accent': const Color(0xFFC5A059),
          'background': const Color(0xFF0F0F0F),
        };
      case 'Ocean Breeze':
        return {
          'primary': const Color(0xFF1A3C47),
          'accent': const Color(0xFF00CED1),
          'background': const Color(0xFF11272C),
        };
      case 'Ocean Pink':
        return {
          'primary': const Color(0xFFFDFBF5),
          'accent': const Color(0xFFFF69B4),
          'background': const Color(0xFFFAF8F0),
        };
      default:
        return {
          'primary': const Color(0xFFFFFFFF),
          'accent': const Color(0xFFC5A059),
          'background': const Color(0xFFFFFCF9),
        };
    }
  }
}
