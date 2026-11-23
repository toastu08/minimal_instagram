// The single source of truth for which destinations the app may visit.
//
// This file is deliberately pure Dart: no Flutter, no WebView, no I/O. It is the
// security boundary of the product, so it must stay small, explicit and fully
// unit-testable. Every navigation in the app — page loads, history changes and
// link clicks inside the page — is judged here.
//
// Design rules:
//   * Deny by default. A route that is not explicitly allowed is blocked.
//   * Match on the URL path only, never on the query string or fragment.
//     Instagram lands on `/?deoia=1` after login; the query must not matter.
//   * Fail closed. Anything unrecognised, malformed or off-site is blocked.

import 'dart:convert';

import 'instagram_routes.dart';

/// What the app should do with a URL.
enum UrlVerdict {
  /// Navigate normally.
  allow,

  /// Do not load this URL; load [UrlDecision.target] instead.
  redirect,

  /// Cancel the navigation and stay where we are.
  block,

  /// Cancel the navigation silently. Used for other apps' URL schemes.
  external,
}

/// The outcome of applying [UrlPolicy] to one URL.
///
/// Immutable and comparable so tests can assert on whole decisions.
final class UrlDecision {
  /// Allows the URL to load.
  const UrlDecision.allow(this.reason)
    : verdict = UrlVerdict.allow,
      target = null;

  /// Refuses the URL, keeping the user on the current page.
  const UrlDecision.block(this.reason)
    : verdict = UrlVerdict.block,
      target = null;

  /// Refuses the URL and loads [target] instead.
  const UrlDecision.redirect(this.target, this.reason)
    : verdict = UrlVerdict.redirect;

  /// Refuses the URL because it belongs to another application or scheme.
  const UrlDecision.external(this.reason)
    : verdict = UrlVerdict.external,
      target = null;

  /// The action to take.
  final UrlVerdict verdict;

  /// Human-readable justification. Goes to the guard log, never to the user.
  final String reason;

  /// Replacement URL when [verdict] is [UrlVerdict.redirect].
  final Uri? target;

  /// True when the navigation must not happen.
  bool get isBlocking =>
      verdict == UrlVerdict.block || verdict == UrlVerdict.external;

  @override
  bool operator ==(Object other) =>
      other is UrlDecision &&
      other.verdict == verdict &&
      other.reason == reason &&
      other.target == target;

  @override
  int get hashCode => Object.hash(verdict, reason, target);

  @override
  String toString() =>
      'UrlDecision(${verdict.name}, ${target ?? '-'}, $reason)';
}

/// How single reels are treated when they are addressable by URL.
///
/// This does not control the in-DM reel viewer, which has no URL of its own.
/// It only decides whether a `/reel/<code>/` link may be opened at all.
enum ReelPolicy {
  /// Allow a reel permalink through. Only meaningful with focus mode, which is
  /// the default for a fresh install.
  allow,

  /// Never open a reel permalink. The guaranteed-safe fallback, exposed as
  /// "Block reels" in Settings.
  block,
}

/// Decides whether a URL may be visited inside the app.
final class UrlPolicy {
  /// Creates a policy.
  ///
  /// [reelPolicy] defaults to [ReelPolicy.block] so a policy built without the
  /// user's choice fails safe. The app passes the persisted setting explicitly.
  const UrlPolicy({ReelPolicy reelPolicy = ReelPolicy.block})
    : this._(
        reelPolicy: reelPolicy,
        hosts: _instagramHosts,
        allowedPorts: _standardPorts,
        fixtureOrigin: null,
      );

  /// A policy that can only reach the local fixture site.
  ///
  /// This exists for the automated on-device tests in `integration_test/`, which
  /// serve `assets/test_site/` with `InAppLocalhostServer` instead of touching
  /// real Instagram (AGENTS.md §6). It is the only way to exercise the
  /// enforcement wiring without a login.
  ///
  /// Production code never constructs this: `browser_screen.dart` defaults to
  /// [UrlPolicy] and nothing in the app passes `fixtureSite`. The route rules
  /// are unchanged, so a forbidden surface is still forbidden; only the origin
  /// differs, and it is a host the app cannot otherwise reach.
  UrlPolicy.fixtureSite({required int port, this.reelPolicy = ReelPolicy.block})
    : _hosts = _fixtureHosts,
      _allowedPorts = <int>{port},
      _fixtureOrigin = 'http://localhost:$port';

  const UrlPolicy._({
    required this.reelPolicy,
    required this._hosts,
    required this._allowedPorts,
    required this._fixtureOrigin,
  });

  /// How single reel permalinks are treated.
  final ReelPolicy reelPolicy;

  /// The hosts this policy can reach.
  final Set<String> _hosts;

  /// The ports this policy can reach. A port outside this set is not the origin
  /// it claims to be, whatever the host string says.
  final Set<int> _allowedPorts;

  /// Non-null only for [UrlPolicy.fixtureSite]; builds the fixture origin.
  final String? _fixtureOrigin;

  /// The page that stands in for the inbox. Instagram's own, except in tests.
  Uri get home => _fixtureOrigin == null
      ? InstagramRoutes.inbox
      : Uri.parse('$_fixtureOrigin/direct/inbox/');

  /// The same rules with a different reel mode.
  ///
  /// Used when the user flips the setting: the host and port rules must survive
  /// the rebuild, so a fixture policy stays a fixture policy.
  UrlPolicy withReelPolicy(ReelPolicy policy) => UrlPolicy._(
    reelPolicy: policy,
    hosts: _hosts,
    allowedPorts: _allowedPorts,
    fixtureOrigin: _fixtureOrigin,
  );

  /// Hosts that serve Instagram's web app.
  static const Set<String> _instagramHosts = <String>{
    'instagram.com',
    'www.instagram.com',
    'm.instagram.com',
  };

  /// The only hosts the fixture site ever uses.
  static const Set<String> _fixtureHosts = <String>{'localhost', '127.0.0.1'};

  /// Ports that are implicit in an ordinary web address.
  static const Set<int> _standardPorts = <int>{80, 443};

  /// Exact paths that are always allowed.
  ///
  /// Every entry is here because a real flow in M0 needed it, or because it is
  /// required to sign in. Do not add routes speculatively.
  static const Set<String> _allowedPaths = <String>{
    // Messaging.
    '/direct/inbox',
    '/direct/requests',
    // Sign-in and recovery. The `auth_platform` subtree is Instagram's own
    // handoff namespace: the login form, account selection, one-tap and the
    // two-factor step all live under it. It is allowed as a prefix (see
    // `_authPlatformPrefix`) because Instagram renames its sub-routes: M0 saw
    // `/auth_platform/codeentry/`, the 2026-11-23 sign-in went through
    // `/auth_platform/afad/` instead.
    '/accounts/login',
    '/accounts/password/reset',
    '/accounts/two_factor',
    '/accounts/onetap',
    // Cookie consent. Observed on a cold start on 2026-11-23: the inbox
    // redirected to `/consent/?flow=user_cookie_choice_v2...`, which the policy
    // blocked, leaving a blank page. The consent page is Instagram's own and is
    // shown once; the app never accepts it on the user's behalf.
    '/consent',
  };

  /// `/challenge/...` is Instagram's security checkpoint. It must be reachable
  /// or a flagged login can never be completed.
  static const String _challengePrefix = '/challenge';

  /// `/auth_platform/...` is Instagram's login handoff. Every sub-route under it
  /// is a step of signing in (login form, account selection, one-tap, two-factor
  /// code entry), so the whole subtree must be reachable or any account with
  /// 2FA enabled — and, over time, every account — becomes unable to sign in.
  ///
  /// Allowed as a prefix rather than an enumerated list because Instagram
  /// changes the sub-route names (`codeentry` in M0, `afad` on 2026-11-23).
  /// This mirrors the `/challenge/` prefix and is not a wildcard over the host.
  static const String _authPlatformPrefix = '/auth_platform';

  /// `/direct/t/<id>/` — one conversation.
  static final RegExp _threadPath = RegExp(r'^/direct/t/[A-Za-z0-9_-]{1,64}$');

  /// `/reel/<code>/` and `/reels/<code>/`. The shortcode is one path segment.
  static final RegExp _reelPath = RegExp(r'^/reels?/([A-Za-z0-9_-]{5,20})$');

  /// `/p/<code>/` — one post. Posts are single items by nature.
  static final RegExp _postPath = RegExp(r'^/p/([A-Za-z0-9_-]{5,20})$');

  /// Judges [uri] and returns what should happen to it.
  UrlDecision decide(Uri uri) {
    if (uri.scheme != 'https' && uri.scheme != 'http') {
      return UrlDecision.external('non-http scheme: ${uri.scheme}');
    }

    // A port outside the policy's set means this is not the origin the host
    // string claims to be.
    if (uri.hasPort && !_allowedPorts.contains(uri.port)) {
      return UrlDecision.block('unexpected port: ${uri.port}');
    }

    if (!_hosts.contains(uri.host.toLowerCase())) {
      return UrlDecision.block('off-site host: ${uri.host}');
    }

    final String path = _normalizePath(uri.path);

    // Landing page: always go straight to messages. The path is checked, not
    // the query, because login lands on `/?deoia=1`.
    if (path == '/') {
      return UrlDecision.redirect(home, 'root -> inbox');
    }

    // `/direct/` itself is Instagram's legacy DM entry point.
    if (path == '/direct') {
      return UrlDecision.redirect(home, 'direct -> inbox');
    }

    if (_allowedPaths.contains(path)) {
      return UrlDecision.allow('allowed path: $path');
    }

    if (_threadPath.hasMatch(path)) {
      return UrlDecision.allow('conversation');
    }

    if (path == _challengePrefix || path.startsWith('$_challengePrefix/')) {
      return UrlDecision.allow('security challenge');
    }

    if (path == _authPlatformPrefix ||
        path.startsWith('$_authPlatformPrefix/')) {
      return UrlDecision.allow('auth platform handoff');
    }

    // Explicit refusals. Deny-by-default already covers these; naming them
    // keeps the guard log readable and documents intent.
    if (path == '/direct/new') {
      return UrlDecision.block('new-message composer is disabled');
    }
    if (path.startsWith('/stories')) {
      return UrlDecision.block('stories are out of scope');
    }
    if (path == '/accounts/signup' || path == '/accounts/emailsignup') {
      return UrlDecision.block('account creation is out of scope');
    }
    if (path == '/accounts/edit' || path == '/accounts/logout') {
      return UrlDecision.block('account surfaces are out of scope');
    }

    if (reelPolicy == ReelPolicy.allow && _reelPath.hasMatch(path)) {
      return UrlDecision.allow('single reel');
    }

    if (_postPath.hasMatch(path)) {
      return UrlDecision.allow('single post');
    }

    return UrlDecision.block('blocked route: $path');
  }

  /// Collapses the root, removes a single trailing slash, and leaves the case
  /// alone: Instagram's paths are case-sensitive, so an unexpected casing must
  /// fall through to the deny-by-default branch.
  static String _normalizePath(String rawPath) {
    if (rawPath.isEmpty) return '/';
    if (rawPath == '/') return '/';
    if (rawPath.endsWith('/')) return rawPath.substring(0, rawPath.length - 1);
    return rawPath;
  }

  /// The same rules, as JSON for the in-page guard script.
  ///
  /// The document-start JavaScript cannot call back into Dart synchronously, so
  /// it needs its own copy of the rules. Generating that copy from this object
  /// means the two can never drift: change the policy here and the script
  /// follows automatically. Never hand-write an allowlist in JavaScript.
  String toGuardRulesJson() {
    return jsonEncode(<String, Object>{
      'hosts': _hosts.toList(),
      'ports': _allowedPorts.toList(),
      'allowedPaths': _allowedPaths.toList(),
      'threadPattern': _threadPath.pattern,
      'reelPattern': _reelPath.pattern,
      'postPattern': _postPath.pattern,
      'challengePrefix': _challengePrefix,
      'authPlatformPrefix': _authPlatformPrefix,
      'reelPolicy': reelPolicy.name,
      'inbox': home.toString(),
    });
  }
}
