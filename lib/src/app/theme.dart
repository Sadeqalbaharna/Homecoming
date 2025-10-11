import 'package:flutter/material.dart';

class AppTheme {
  static const _seed = Color(0xFF3A7BDC);

  static final light = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(seedColor: _seed, brightness: Brightness.light),
  );

  static final dark = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(seedColor: _seed, brightness: Brightness.dark),
  );
}