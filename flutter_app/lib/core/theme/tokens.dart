import 'package:flutter/widgets.dart';

/// Spacing scale (4/8 grid). Use these instead of raw numbers.
abstract final class Space {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
}

abstract final class Radii {
  static const double card = 12;
  static const double input = 8;
  static const double pill = 999;
  static const BorderRadius cardAll = BorderRadius.all(Radius.circular(card));
  static const BorderRadius inputAll = BorderRadius.all(Radius.circular(input));
}

/// Layout breakpoints.
abstract final class Breakpoints {
  /// Sidebar + desktop layouts from here up.
  static const double desktop = 1024;

  /// Two-column card grids from here up.
  static const double tablet = 640;

  /// Max width of page content on large screens.
  static const double contentMax = 1200;
  static const double sidebarWidth = 248;
}
