// WebView configuration.
//
// One factory, used everywhere, so the security-relevant settings cannot drift
// between screens. Anything that changes here changes the app's behavior.

import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../core/config/app_config.dart';

/// Builds the settings for the app's only WebView.
InAppWebViewSettings buildWebViewSettings() {
  return InAppWebViewSettings(
    userAgent: AppConfig.userAgent,

    // Instagram is a client-side app; without these it renders nothing.
    javaScriptEnabled: true,
    domStorageEnabled: true,
    databaseEnabled: true,
    thirdPartyCookiesEnabled: true,

    // The guard lives in `shouldOverrideUrlLoading`, which is only called when
    // this is enabled. Turning it off silently disables URL enforcement.
    useShouldOverrideUrlLoading: true,

    // No second WebView may ever be created. `target="_blank"` and window.open
    // are denied by the guard script as well.
    supportMultipleWindows: false,

    // Reels are video-first; requiring a user gesture would stall playback.
    mediaPlaybackRequiresUserGesture: false,
    allowsInlineMediaPlayback: true,

    cacheEnabled: true,

    // Debug-only remote inspection. A release build must never expose its web
    // contents to the host machine.
    isInspectable: kDebugMode,
  );
}
