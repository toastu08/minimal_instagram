// Classifies movement between the two direct-message surfaces the app animates.
//
// The inbox and a conversation live in the same WebView; Instagram swaps them
// with `history.pushState`, so there is no Flutter route to animate. This pure
// helper answers the only question the motion layer needs: did the user move
// "into" a conversation or "out of" one? It knows nothing about Flutter and
// nothing about policy verdicts — `UrlPolicy` still decides what is allowed.
// A unit test pins these path shapes to `UrlPolicy` so the two cannot drift.

/// A movement between direct-message surfaces that the app may animate.
enum DmTransition {
  /// Inbox -> conversation. The conversation should arrive from the right.
  forward,

  /// Conversation -> inbox. The inbox should arrive from the left.
  back,

  /// No direct-message level change: same level, another surface, or a reload.
  none,
}

/// Inbox-level paths: the DM list and message requests.
const Set<String> _inboxPaths = <String>{'/direct/inbox', '/direct/requests'};

/// `/direct/t/<id>` — one conversation. Mirrors `UrlPolicy`'s thread rule.
final RegExp _threadPath = RegExp(r'^/direct/t/[A-Za-z0-9_-]{1,64}$');

/// Classifies a move from [from] to [to].
///
/// Only the path is considered: query strings and fragments change constantly
/// (Instagram appends tracking parameters) and carry no surface information.
/// Anything that is not a cross-level move between the DM surfaces is [none].
DmTransition classifyDmTransition(Uri from, Uri to) {
  final _DmSurface before = _surfaceOf(from.path);
  final _DmSurface after = _surfaceOf(to.path);

  if (before == _DmSurface.inbox && after == _DmSurface.thread) {
    return DmTransition.forward;
  }
  if (before == _DmSurface.thread && after == _DmSurface.inbox) {
    return DmTransition.back;
  }
  return DmTransition.none;
}

/// The three path classes this file cares about.
enum _DmSurface { inbox, thread, other }

/// Classifies one path, applying the same trailing-slash rule as `UrlPolicy`.
_DmSurface _surfaceOf(String rawPath) {
  final String path = _normalize(rawPath);
  if (_inboxPaths.contains(path)) return _DmSurface.inbox;
  if (_threadPath.hasMatch(path)) return _DmSurface.thread;
  return _DmSurface.other;
}

/// Collapses the root and removes one trailing slash, matching `UrlPolicy`.
String _normalize(String rawPath) {
  if (rawPath.isEmpty || rawPath == '/') return '/';
  if (rawPath.endsWith('/')) return rawPath.substring(0, rawPath.length - 1);
  return rawPath;
}
