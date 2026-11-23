// Runtime settings that survive an app restart.
//
// Only one value is stored today: whether shared reels are blocked. Nothing
// about the user, the session or the messages is ever written here. The
// WebView's own cookie jar is the only place the session lives (AGENTS.md §2.4).
//
// `shared_preferences` is used instead of a hand-rolled file because Android's
// app-data directory is not reachable from Dart without another plugin, and a
// native platform channel would be more code to own than one small, official
// Flutter plugin. The justification is recorded in PROGRESS.md §14.

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../navigation/url_policy.dart';

/// The app's persisted preferences.
///
/// Read once at startup, before the WebView exists, so the document-start guard
/// is generated with the user's chosen reel mode on the very first page.
final class AppSettings {
  AppSettings._(this._prefs, this.reelPolicy);

  /// Preference key. Never rename without a migration: it is the only stored
  /// state the app has.
  static const String _blockReelsKey = 'reels_blocked';

  final SharedPreferences _prefs;

  /// The live reel mode.
  ///
  /// A [ValueNotifier] rather than a package: the browser screen listens, rebuilds
  /// its policy and reloads the page when the user flips the switch.
  final ValueNotifier<ReelPolicy> reelPolicy;

  /// Reads the stored preferences.
  ///
  /// Defaults to [ReelPolicy.allow] (Single reel, the product default). If the
  /// store cannot be read, the same default applies: a failed read must not
  /// silently switch the app into a mode the user did not choose.
  static Future<AppSettings> load() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final bool blocked = prefs.getBool(_blockReelsKey) ?? false;
    return AppSettings._(
      prefs,
      ValueNotifier<ReelPolicy>(blocked ? ReelPolicy.block : ReelPolicy.allow),
    );
  }

  /// Changes the reel mode and persists it.
  ///
  /// The notifier updates first so the UI responds immediately; a failed write
  /// leaves the choice in force for this run rather than throwing in the user's
  /// face.
  Future<void> setBlockReels(bool blocked) async {
    final ReelPolicy next = blocked ? ReelPolicy.block : ReelPolicy.allow;
    if (next == reelPolicy.value) return;
    reelPolicy.value = next;
    await _prefs.setBool(_blockReelsKey, blocked);
  }
}
