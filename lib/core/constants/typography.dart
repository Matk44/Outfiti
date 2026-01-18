import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Typography constants for consistent text styling across the app
/// Uses Playfair Display for elegant headings and Plus Jakarta Sans for body text
class AppTypography {
  // Headings use Playfair Display (serif)
  static TextStyle heading1(Color color) => GoogleFonts.playfairDisplay(
        fontSize: 32,
        fontWeight: FontWeight.bold,
        color: color,
        letterSpacing: 0.5,
      );

  static TextStyle heading2(Color color) => GoogleFonts.playfairDisplay(
        fontSize: 24,
        fontWeight: FontWeight.w600,
        color: color,
        letterSpacing: 0.5,
      );

  static TextStyle heading3(Color color) => GoogleFonts.playfairDisplay(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: color,
        letterSpacing: 0,
      );

  // Body text uses Plus Jakarta Sans
  static TextStyle bodyLarge(Color color) => GoogleFonts.plusJakartaSans(
        fontSize: 16,
        fontWeight: FontWeight.w400,
        color: color,
        letterSpacing: 0.15,
      );

  static TextStyle bodyMedium(Color color) => GoogleFonts.plusJakartaSans(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: color,
        letterSpacing: 0.25,
      );

  static TextStyle bodySmall(Color color) => GoogleFonts.plusJakartaSans(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        color: color,
        letterSpacing: 0.4,
      );

  // Buttons and labels use Plus Jakarta Sans with wider tracking
  static TextStyle button(Color color) => GoogleFonts.plusJakartaSans(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: color,
        letterSpacing: 1.5,
      );

  // Small labels (like "TRANSFORMATION", "EXQUISITE RESULT")
  static TextStyle label(Color color) => GoogleFonts.plusJakartaSans(
        fontSize: 10,
        fontWeight: FontWeight.w600,
        color: color,
        letterSpacing: 2.0,
      );

  // Subtitle text (elegant small caps style)
  static TextStyle subtitle(Color color) => GoogleFonts.plusJakartaSans(
        fontSize: 9,
        fontWeight: FontWeight.w500,
        color: color,
        letterSpacing: 2.5,
      );
}
