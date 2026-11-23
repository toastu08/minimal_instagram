// Compile-time app configuration.
//
// Values that would otherwise be scattered as magic strings. User-configurable
// state lives in `core/settings/app_settings.dart`.

import '../../navigation/instagram_routes.dart';

/// Static app configuration.
abstract final class AppConfig {
  /// The version shown in Settings.
  ///
  /// Keep in sync with `version:` in `pubspec.yaml`; a unit test enforces it.
  static const String version = '1.0.0';

  /// A plain Chrome-on-Android user agent.
  ///
  /// The default Android WebView UA contains the `wv` token, which Instagram
  /// treats as an unsupported embedded browser. M0 proved this string works.
  static const String userAgent =
      'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/140.0.0.0 Mobile Safari/537.36';

  /// The page the app opens. Starting at the inbox means the feed never loads,
  /// even for a moment. Instagram redirects to login when there is no session.
  static Uri get startUrl => InstagramRoutes.inbox;

  /// How many guard decisions to keep in memory for the debug screen.
  static const int guardLogCapacity = 200;
}
