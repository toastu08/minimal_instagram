// Compile-time app configuration.
//
// Values that would otherwise be scattered as magic strings. Nothing here is
// user-configurable yet; runtime settings arrive in M6.

import '../../navigation/instagram_routes.dart';
import '../../navigation/url_policy.dart';

/// Static app configuration.
abstract final class AppConfig {
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

  /// How reel permalinks are treated.
  ///
  /// Focus mode is the default from M5. `--dart-define=MI_BLOCK_REELS=true`
  /// selects the guaranteed-safe Mode B (SPEC §5.2) and is how M5's fallback is
  /// tested by hand. M6 replaces this switch with a persisted setting.
  static const bool _blockReels = bool.fromEnvironment('MI_BLOCK_REELS');

  /// The reel mode in force for this build.
  static const ReelPolicy reelPolicy = _blockReels
      ? ReelPolicy.block
      : ReelPolicy.allow;

  /// How many guard decisions to keep in memory for the debug screen.
  static const int guardLogCapacity = 200;
}
