// Entry point.
//
// Kept to the absolute minimum: Flutter setup, WebView debugging in debug
// builds, then hand over to the app. No business logic belongs here.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Lets `chrome://inspect` on the host machine attach to the WebView. Debug
  // builds only: a release build must never expose its web contents.
  if (kDebugMode) {
    InAppWebViewController.setWebContentsDebuggingEnabled(true);
  }

  runApp(const MinimalInstagramApp());
}
