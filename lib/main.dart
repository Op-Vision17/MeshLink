import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'presentation/screens/splash_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: Color(0xFF0A0A14),
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );
  runApp(
    const ProviderScope(
      child: MeshLinkApp(),
    ),
  );
}

// ── MeshLink Design Tokens ───────────────────────────────────────────────────

class MeshColors {
  MeshColors._();

  // Surfaces
  static const Color background = Color(0xFF0A0A14);
  static const Color surface = Color(0xFF12121F);
  static const Color surfaceElevated = Color(0xFF1A1A2E);
  static const Color surfaceHighlight = Color(0xFF222240);

  // Accents
  static const Color primary = Color(0xFF4F46E5);       // Indigo
  static const Color primaryLight = Color(0xFF6366F1);   // Lighter indigo
  static const Color secondary = Color(0xFF7C3AED);      // Violet
  static const Color accent = Color(0xFF4361EE);          // Blue
  
  // Semantic
  static const Color success = Color(0xFF10B981);
  static const Color warning = Color(0xFFF59E0B);
  static const Color error = Color(0xFFEF4444);
  static const Color info = Color(0xFF3B82F6);

  // Text
  static const Color textPrimary = Color(0xFFF9FAFB);
  static const Color textSecondary = Color(0xFF9CA3AF);
  static const Color textTertiary = Color(0xFF6B7280);
  static const Color textDisabled = Color(0xFF4B5563);

  // Borders
  static const Color border = Color(0xFF1F2937);
  static const Color borderSubtle = Color(0xFF1A1A2E);
  static const Color borderAccent = Color(0x404F46E5);

  // Gradients
  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primary, secondary],
  );

  static const LinearGradient surfaceGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF15152A), Color(0xFF0A0A14)],
  );
}

class MeshLinkApp extends StatelessWidget {
  const MeshLinkApp({super.key});

  @override
  Widget build(BuildContext context) {
    final textTheme = GoogleFonts.interTextTheme(
      ThemeData.dark().textTheme,
    );

    return MaterialApp(
      title: 'MeshLink',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        scaffoldBackgroundColor: MeshColors.background,
        colorScheme: ColorScheme.dark(
          primary: MeshColors.primary,
          secondary: MeshColors.secondary,
          surface: MeshColors.surface,
          error: MeshColors.error,
          onPrimary: Colors.white,
          onSecondary: Colors.white,
          onSurface: MeshColors.textPrimary,
          onError: Colors.white,
        ),
        textTheme: textTheme.copyWith(
          headlineLarge: textTheme.headlineLarge?.copyWith(
            color: MeshColors.textPrimary,
            fontWeight: FontWeight.w700,
          ),
          headlineMedium: textTheme.headlineMedium?.copyWith(
            color: MeshColors.textPrimary,
            fontWeight: FontWeight.w600,
          ),
          titleLarge: textTheme.titleLarge?.copyWith(
            color: MeshColors.textPrimary,
            fontWeight: FontWeight.w600,
          ),
          titleMedium: textTheme.titleMedium?.copyWith(
            color: MeshColors.textPrimary,
            fontWeight: FontWeight.w500,
          ),
          bodyLarge: textTheme.bodyLarge?.copyWith(
            color: MeshColors.textPrimary,
          ),
          bodyMedium: textTheme.bodyMedium?.copyWith(
            color: MeshColors.textSecondary,
          ),
          bodySmall: textTheme.bodySmall?.copyWith(
            color: MeshColors.textTertiary,
          ),
          labelLarge: textTheme.labelLarge?.copyWith(
            color: MeshColors.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        appBarTheme: AppBarTheme(
          backgroundColor: MeshColors.surface,
          foregroundColor: MeshColors.textPrimary,
          elevation: 0,
          centerTitle: true,
          titleTextStyle: GoogleFonts.inter(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: MeshColors.textPrimary,
          ),
        ),
        cardTheme: CardThemeData(
          color: MeshColors.surface,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: MeshColors.border, width: 1),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: MeshColors.primary,
            foregroundColor: Colors.white,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            textStyle: GoogleFonts.inter(
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: MeshColors.primary,
            side: const BorderSide(color: MeshColors.primary),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: MeshColors.background,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: MeshColors.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: MeshColors.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: MeshColors.primary, width: 1.5),
          ),
          hintStyle: GoogleFonts.inter(color: MeshColors.textDisabled),
        ),
        dividerTheme: const DividerThemeData(
          color: MeshColors.border,
          thickness: 0.5,
        ),
      ),
      home: const SplashScreen(),
    );
  }
}
