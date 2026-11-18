// Canonical Instagram URLs used by the app.
//
// Every Instagram URL the app builds or compares against is defined here so
// that no screen or controller has to assemble one by hand. Navigation *rules*
// live in `url_policy.dart`; this file only knows the shape of the addresses.

/// Instagram's canonical web origin. All app-initiated navigation uses it.
abstract final class InstagramRoutes {
  /// The origin every in-app URL is built from.
  static const String origin = 'https://www.instagram.com';

  /// Instagram's own login page. The app never renders a login form itself.
  static final Uri login = Uri.parse('$origin/accounts/login/');

  /// The app's home: the direct-message inbox.
  static final Uri inbox = Uri.parse('$origin/direct/inbox/');

  /// Message requests. Still direct messages, so still allowed.
  static final Uri requests = Uri.parse('$origin/direct/requests/');

  /// A conversation with a specific thread id.
  static Uri thread(String threadId) =>
      Uri.parse('$origin/direct/t/$threadId/');

  /// A single reel, addressable only outside the in-DM viewer (which has no
  /// URL of its own).
  static Uri reel(String shortcode) => Uri.parse('$origin/reel/$shortcode/');

  /// A single post.
  static Uri post(String shortcode) => Uri.parse('$origin/p/$shortcode/');
}
