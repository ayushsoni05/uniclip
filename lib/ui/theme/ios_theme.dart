import 'package:flutter/cupertino.dart';

class IOSTheme {
  // === Colors (exact iOS 17 system colors) ===
  static const Color systemBlue = Color(0xFF007AFF);
  static const Color systemGreen = Color(0xFF34C759);
  static const Color systemRed = Color(0xFFFF3B30);
  static const Color systemOrange = Color(0xFFFF9500);
  static const Color systemYellow = Color(0xFFFFCC00);
  static const Color systemGray = Color(0xFF8E8E93);
  static const Color systemGray2 = Color(0xFFAEAEB2);
  static const Color systemGray3 = Color(0xFFC7C7CC);
  static const Color systemGray4 = Color(0xFFD1D1D6);
  static const Color systemGray5 = Color(0xFFE5E5EA);
  static const Color systemGray6 = Color(0xFFF2F2F7);
  static const Color separator = Color(0xFFC6C6C8);
  static const Color systemGroupedBackground = Color(0xFFF2F2F7);
  static const Color secondarySystemGroupedBackground = Color(0xFFFFFFFF);
  static const Color label = Color(0xFF000000);
  static const Color secondaryLabel = Color(0xFF3C3C43); // 60% opacity
  static const Color tertiaryLabel = Color(0xFF3C3C43); // 30% opacity
  
  // === Typography ===
  static const double largeTitleSize = 34.0;
  static const double title1Size = 28.0;
  static const double title2Size = 22.0;
  static const double title3Size = 20.0;
  static const double headlineSize = 17.0;
  static const double bodySize = 17.0;
  static const double calloutSize = 16.0;
  static const double subheadSize = 15.0;
  static const double footnoteSize = 13.0;
  static const double caption1Size = 12.0;
  static const double caption2Size = 11.0;
  
  // === Spacing ===
  static const double sectionSpacing = 35.0;
  static const double cellHeight = 44.0;
  static const double horizontalPadding = 16.0;
  static const double groupedInset = 20.0;
  
  // === CupertinoThemeData ===
  static CupertinoThemeData get theme => const CupertinoThemeData(
    brightness: Brightness.light,
    primaryColor: systemBlue,
    primaryContrastingColor: CupertinoColors.white,
    scaffoldBackgroundColor: systemGroupedBackground,
    barBackgroundColor: Color(0xF0F9F9F9), // Translucent nav bar
    textTheme: CupertinoTextThemeData(
      primaryColor: systemBlue,
      actionTextStyle: TextStyle(
        color: systemBlue,
        fontSize: 17.0,
      ),
    ),
  );
}
