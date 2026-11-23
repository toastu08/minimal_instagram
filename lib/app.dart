// Application root: theme and the single top-level route.
//
// Deliberately thin. The app has one screen (the browser) plus a settings sheet,
// so there is no router package and no nested navigation graph.

import 'package:flutter/material.dart';

import 'core/settings/app_settings.dart';
import 'webview/browser_screen.dart';

/// The root widget.
class MinimalInstagramApp extends StatelessWidget {
  /// Creates the app.
  const MinimalInstagramApp({super.key, required this.settings});

  /// Persisted preferences, loaded before the first frame.
  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Minimal Instagram',
      debugShowCheckedModeBanner: false,
      theme: _themeFor(Brightness.light),
      darkTheme: _themeFor(Brightness.dark),
      home: BrowserScreen(settings: settings),
    );
  }

  /// A quiet, neutral theme: the app should disappear behind Instagram's UI.
  static ThemeData _themeFor(Brightness brightness) {
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorSchemeSeed: const Color(0xFF3F5C57),
      appBarTheme: const AppBarTheme(centerTitle: false),
    );
  }
}
