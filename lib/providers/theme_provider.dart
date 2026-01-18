import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/constants/typography.dart';

class ThemeProvider with ChangeNotifier {
  String _selectedTheme = 'Divine Gold';
  SharedPreferences? _prefs;

  final Map<String, Map<String, dynamic>> _themes = {
    'Divine Gold': {
      'primary': const Color(0xFFFFFFFF),
      'background': const Color(0xFFFFFCF9),
      'surface': const Color(0xFFFFFFFF),
      'accent': const Color(0xFFC5A059),
      'accentDark': const Color(0xFF9D7F44),
      'accentLight': const Color(0xFFD4AF37),
      'textPrimary': const Color(0xFF2C2825),
      'textSecondary': const Color(0xFF7D7671),
      'isDark': false,
    },
    'Obsidian Night': {
      'primary': const Color(0xFF1A1A1A),
      'background': const Color(0xFF0F0F0F),
      'surface': const Color(0xFF1A1A1A),
      'accent': const Color(0xFFC5A059),
      'textPrimary': Colors.white,
      'textSecondary': Colors.white.withValues(alpha: 0.7),
      'isDark': true,
    },
    'Peaches & Cream': {
      'primary': const Color(0xFFE8E4E1),
      'background': const Color(0xFFF5F3F0),
      'surface': const Color(0xFFFCFBFA),
      'accent': const Color(0xFFFF8E72),
      'textPrimary': const Color(0xFF1A1A1A),
      'textSecondary': const Color(0xFF5A5A5A),
      'isDark': false,
    },
    'Midnight Purple': {
      'primary': const Color(0xFF2C1A47),
      'background': const Color(0xFF1A1127),
      'surface': const Color(0xFF2C1A47),
      'accent': const Color(0xFFFFD700),
      'textPrimary': Colors.white,
      'textSecondary': Colors.white.withValues(alpha: 0.7),
      'isDark': true,
    },
    'Forest Whisper': {
      'primary': const Color(0xFF2C472C),
      'background': const Color(0xFF1A271A),
      'surface': const Color(0xFF2C472C),
      'accent': const Color(0xFF98FB98),
      'textPrimary': Colors.white,
      'textSecondary': Colors.white.withValues(alpha: 0.7),
      'isDark': true,
    },
    'Sunset Glow': {
      'primary': const Color(0xFF473C1A),
      'background': const Color(0xFF272111),
      'surface': const Color(0xFF473C1A),
      'accent': const Color(0xFFFFA500),
      'textPrimary': Colors.white,
      'textSecondary': Colors.white.withValues(alpha: 0.7),
      'isDark': true,
    },
    'Twilight Rose': {
      'primary': const Color(0xFF4A2C47),
      'background': const Color(0xFF271A25),
      'surface': const Color(0xFF4A2C47),
      'accent': const Color(0xFFFF69B4),
      'textPrimary': Colors.white,
      'textSecondary': Colors.white.withValues(alpha: 0.7),
      'isDark': true,
    },
    'Ocean Breeze': {
      'primary': const Color(0xFF1A3C47),
      'background': const Color(0xFF11272C),
      'surface': const Color(0xFF1A3C47),
      'accent': const Color(0xFF00CED1),
      'textPrimary': Colors.white,
      'textSecondary': Colors.white.withValues(alpha: 0.7),
      'isDark': true,
    },
    'Ocean Pink': {
      'primary': const Color(0xFFFDFBF5),
      'background': const Color(0xFFFAF8F0),
      'surface': const Color(0xFFFEFEFB),
      'accent': const Color(0xFFFF69B4),
      'textPrimary': const Color(0xFF1A1A1A),
      'textSecondary': const Color(0xFF5A5A5A),
      'isDark': false,
    },
  };

  String get selectedTheme => _selectedTheme;

  Map<String, dynamic> get currentThemeData =>
      _themes[_selectedTheme] ?? _themes['Divine Gold']!;

  List<String> get availableThemes => _themes.keys.toList();

  ThemeData get currentTheme {
    final themeData = currentThemeData;
    final isDark = themeData['isDark'] as bool;

    return ThemeData(
      brightness: isDark ? Brightness.dark : Brightness.light,
      primarySwatch: _createMaterialColor(themeData['primary'] as Color),
      primaryColor: themeData['primary'] as Color,
      scaffoldBackgroundColor: themeData['background'] as Color,
      cardColor: themeData['surface'] as Color,
      fontFamily: GoogleFonts.plusJakartaSans().fontFamily,
      colorScheme: ColorScheme(
        brightness: isDark ? Brightness.dark : Brightness.light,
        primary: themeData['primary'] as Color,
        onPrimary: isDark ? Colors.white : Colors.black,
        secondary: themeData['accent'] as Color,
        onSecondary: isDark ? Colors.black : Colors.white,
        error: Colors.red,
        onError: Colors.white,
        surface: themeData['surface'] as Color,
        onSurface: themeData['textPrimary'] as Color,
        outline: themeData['textSecondary'] as Color,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: themeData['textPrimary'] as Color,
        elevation: 0,
        centerTitle: true,
        titleTextStyle:
            AppTypography.heading2(themeData['textPrimary'] as Color),
      ),
      cardTheme: CardThemeData(
        color: themeData['surface'] as Color,
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: themeData['accent'] as Color,
          foregroundColor: isDark ? Colors.black : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        ),
      ),
      textTheme: TextTheme(
        headlineLarge:
            AppTypography.heading1(themeData['textPrimary'] as Color),
        headlineMedium:
            AppTypography.heading2(themeData['textPrimary'] as Color),
        headlineSmall:
            AppTypography.heading3(themeData['textPrimary'] as Color),
        bodyLarge: AppTypography.bodyLarge(themeData['textPrimary'] as Color),
        bodyMedium:
            AppTypography.bodyMedium(themeData['textPrimary'] as Color),
        bodySmall:
            AppTypography.bodySmall(themeData['textSecondary'] as Color),
        labelLarge: AppTypography.button(themeData['textPrimary'] as Color),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: themeData['surface'] as Color,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: themeData['accent'] as Color,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: themeData['accent'] as Color,
            width: 2,
          ),
        ),
        labelStyle:
            AppTypography.bodyMedium(themeData['textSecondary'] as Color),
        hintStyle:
            AppTypography.bodyMedium(themeData['textSecondary'] as Color),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: themeData['accent'] as Color,
        selectionColor: (themeData['accent'] as Color).withValues(alpha: 0.3),
        selectionHandleColor: themeData['accent'] as Color,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: themeData['surface'] as Color,
        titleTextStyle:
            AppTypography.heading2(themeData['textPrimary'] as Color),
        contentTextStyle:
            AppTypography.bodyMedium(themeData['textPrimary'] as Color),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
    );
  }

  List<Color> get backgroundGradientColors {
    if (_selectedTheme == 'Divine Gold') {
      return [
        const Color(0xFFFFFCF9),
        const Color(0xFFF9F5EB),
        const Color(0xFFFFFFFF),
      ];
    } else if (_selectedTheme == 'Ocean Breeze') {
      return [
        const Color(0xFF1A3C47),
        const Color(0xFF11272C),
        const Color(0xFF0A1B1F),
      ];
    } else if (isDarkTheme) {
      return [
        primaryColor,
        backgroundColor,
        backgroundColor.withValues(alpha: 0.8),
      ];
    } else {
      return [
        backgroundColor,
        backgroundColor,
        backgroundColor.withValues(alpha: 0.9),
      ];
    }
  }

  MaterialColor _createMaterialColor(Color color) {
    List strengths = <double>[.05];
    Map<int, Color> swatch = {};
    final int r = (color.r * 255).round();
    final int g = (color.g * 255).round();
    final int b = (color.b * 255).round();

    for (int i = 1; i < 10; i++) {
      strengths.add(0.1 * i);
    }
    for (var strength in strengths) {
      final double ds = 0.5 - strength;
      swatch[(strength * 1000).round()] = Color.fromRGBO(
        r + ((ds < 0 ? r : (255 - r)) * ds).round(),
        g + ((ds < 0 ? g : (255 - g)) * ds).round(),
        b + ((ds < 0 ? b : (255 - b)) * ds).round(),
        1,
      );
    }
    return MaterialColor(color.toARGB32(), swatch);
  }

  Future<void> initializeTheme() async {
    _prefs = await SharedPreferences.getInstance();
    final savedTheme = _prefs?.getString('selected_theme') ?? 'Divine Gold';

    if (_themes.containsKey(savedTheme)) {
      _selectedTheme = savedTheme;
    } else {
      _selectedTheme = 'Divine Gold';
      await _prefs?.setString('selected_theme', 'Divine Gold');
    }

    notifyListeners();
  }

  Future<void> setTheme(String themeName) async {
    if (_themes.containsKey(themeName)) {
      _selectedTheme = themeName;
      await _prefs?.setString('selected_theme', themeName);
      notifyListeners();
    }
  }

  // Convenient accessors for current theme
  Color get primaryColor => currentThemeData['primary'] as Color;
  Color get backgroundColor => currentThemeData['background'] as Color;
  Color get surfaceColor => currentThemeData['surface'] as Color;
  Color get accentColor => currentThemeData['accent'] as Color;
  Color get textPrimaryColor => currentThemeData['textPrimary'] as Color;
  Color get textSecondaryColor => currentThemeData['textSecondary'] as Color;
  bool get isDarkTheme => currentThemeData['isDark'] as bool;

  Map<String, Color> get currentThemeColors => {
        'primary': primaryColor,
        'background': backgroundColor,
        'surface': surfaceColor,
        'accent': accentColor,
      };
}
