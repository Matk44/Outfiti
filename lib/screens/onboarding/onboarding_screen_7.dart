import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/theme_provider.dart';

class OnboardingScreen7 extends StatelessWidget {
  const OnboardingScreen7({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final theme = Theme.of(context);
    final screenHeight = MediaQuery.of(context).size.height;

    return Scaffold(
      backgroundColor: themeProvider.backgroundColor,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(),

              // Badge image - fill most of screen width
              Image.asset(
                'assets/icons/badge.png',
                width: MediaQuery.of(context).size.width * 0.85,
                fit: BoxFit.contain,
              ),

              SizedBox(height: screenHeight * 0.06),

              // Text below badge
              Text(
                'Built using cutting-edge generative vision models',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                  color: themeProvider.textPrimaryColor,
                  height: 1.4,
                ),
              ),

              const SizedBox(height: 12),

              Text(
                'Trained to preserve identity—not distort it',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w400,
                  color: themeProvider.textSecondaryColor,
                  height: 1.4,
                ),
              ),

              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}
