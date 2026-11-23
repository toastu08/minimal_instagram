// Entry point.
//
// Kept to the absolute minimum: Flutter setup, persisted settings, WebView
// debugging in debug builds, then hand over to the app. No business logic
// belongs here.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'app.dart';
import 'core/settings/app_settings.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Lets `chrome://inspect` on the host machine attach to the WebView. Debug
  // builds only: a release build must never expose its web contents.
  if (kDebugMode) {
    InAppWebViewController.setWebContentsDebuggingEnabled(true);
  }

  // Loaded before `runApp` so the very first document is guarded with the
  // user's chosen reel mode. A slow read is still better than a flash of the
  // wrong rules.
  final AppSettings settings = await AppSettings.load();

  runApp(MinimalInstagramApp(settings: settings));
}
