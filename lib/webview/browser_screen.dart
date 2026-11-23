// The app's only screen: a WebView that hosts Instagram, plus the enforcement
// wiring that makes "messages only" true.
//
// Responsibilities, in order of importance:
//   1. Refuse every disallowed navigation, through all three layers:
//      native URL override, history-change backstop, and the in-page guard.
//   2. Keep the user on a usable page when something is refused.
//   3. Present loading, error and offline states.
//   4. Hand the Android back button a sane, non-escaping behavior.
//
// It contains no Instagram selectors and no URL rules. Those live in
// `assets/css`, `assets/js` and `UrlPolicy` respectively.

import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../core/config/app_config.dart';
import '../core/logging/guard_log.dart';
import '../core/settings/app_settings.dart';
import '../navigation/instagram_routes.dart';
import '../navigation/url_policy.dart';
import '../ui/common/error_view.dart';
import '../ui/debug/debug_screen.dart';
import '../ui/settings/settings_sheet.dart';
import 'webview_settings.dart';

/// Hosts Instagram and enforces the URL policy.
class BrowserScreen extends StatefulWidget {
  /// Creates the screen.
  const BrowserScreen({super.key, required this.settings});

  /// Persisted preferences, owned by the app root.
  final AppSettings settings;

  @override
  State<BrowserScreen> createState() => _BrowserScreenState();
}

class _BrowserScreenState extends State<BrowserScreen> {
  /// The policy in force. Rebuilt when the user changes the reels preference.
  late UrlPolicy _policy = UrlPolicy(
    reelPolicy: widget.settings.reelPolicy.value,
  );

  /// Shared decision log, read by the debug screen.
  final GuardLog _log = GuardLog(capacity: AppConfig.guardLogCapacity);

  InAppWebViewController? _controller;

  /// The document-start bundle: rules + navigation guard + sanitizer.
  ///
  /// Null until the assets have loaded. The WebView is not created before then,
  /// because the guard must be present on the very first document.
  String? _guardSource;

  String _currentUrl = '';
  bool _isLoading = true;
  double _progress = 0;
  FailureKind? _failure;
  String? _failureDetail;

  /// True while the in-page reel viewer is open and frozen.
  ///
  /// Owned by the page: the viewer has no URL, so this is the only signal that
  /// it is on screen. Drives the "Single reel" banner and the back button.
  bool _reelOpen = false;

  /// Rate-limits the "not available" notice so repeated blocks do not spam.
  DateTime? _lastBlockNotice;

  /// True once a DM page has loaded in this run.
  ///
  /// Used to tell a real session expiry apart from a first launch with no
  /// session: both end up on the login page, but only one deserves a notice.
  bool _sawAuthenticatedPage = false;

  /// True while the user is deliberately clearing the session, so the resulting
  /// login page is not reported as an expiry.
  bool _clearingSession = false;

  @override
  void initState() {
    super.initState();
    widget.settings.reelPolicy.addListener(_onReelPolicyChanged);
    unawaited(_loadGuardScript());
  }

  @override
  void dispose() {
    widget.settings.reelPolicy.removeListener(_onReelPolicyChanged);
    super.dispose();
  }

  /// Applies a reels-preference change.
  ///
  /// The navigation policy changes immediately, but the in-page guard only reads
  /// its rules at document start, so the page is reloaded after the bundle is
  /// rebuilt. Reloading also leaves any open reel viewer, which is the safe
  /// outcome when switching to "Block reels".
  void _onReelPolicyChanged() {
    if (!mounted) return;
    setState(() {
      _policy = UrlPolicy(reelPolicy: widget.settings.reelPolicy.value);
    });
    unawaited(_applyReelPolicy());
  }

  Future<void> _applyReelPolicy() async {
    await _loadGuardScript();
    final InAppWebViewController? controller = _controller;
    final String? source = _guardSource;
    if (!mounted || controller == null || source == null) return;

    // `initialUserScripts` is only read when the platform WebView is created.
    // Rebuilding the widget does not replace the script on an existing WebView,
    // so the old rules would survive the reload. Replace them explicitly.
    await controller.removeAllUserScripts();
    await controller.addUserScript(
      userScript: UserScript(
        source: source,
        injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
      ),
    );
    await controller.reload();
  }

  /// Builds one document-start script, in a fixed order.
  ///
  /// Concatenated rather than injected as separate user scripts so the order is
  /// guaranteed: the rule set must exist before the guard reads it, and the
  /// stylesheet text must exist before the sanitizer injects it.
  Future<void> _loadGuardScript() async {
    final List<String> assets = await Future.wait(<Future<String>>[
      rootBundle.loadString('assets/js/guard_document_start.js'),
      rootBundle.loadString('assets/js/guard_load.js'),
      rootBundle.loadString('assets/css/hide_instagram_chrome.css'),
    ]);
    if (!mounted) return;

    final String css = assets[2];
    // The version lives in the CSS header comment; parsing it keeps the report
    // honest without a second place to bump.
    final RegExpMatch? versionMatch = RegExp(r'sanitizer-version:\s*(\d+)')
        .firstMatch(css);

    setState(() {
      _guardSource = <String>[
        'window.__MI_RULES = ${_policy.toGuardRulesJson()};',
        'window.__MI_SANITIZER = ${jsonEncode(<String, String>{'version': versionMatch?.group(1) ?? '0', 'css': css})};',
        assets[0],
        assets[1],
      ].join('\n');
    });
  }

  // ------------------------------------------------------------------ wiring

  void _onWebViewCreated(InAppWebViewController controller) {
    _controller = controller;

    // Reports from the in-page guard. Fired for pushState vetoes, blocked
    // anchor clicks and denied popups, where no native callback exists.
    controller.addJavaScriptHandler(
      handlerName: 'miNavigationBlocked',
      callback: (List<dynamic> args) {
        final String url = args.isNotEmpty ? args[0].toString() : '';
        final String verdictName = args.length > 1
            ? args[1].toString()
            : 'block';
        final String source = args.length > 2 ? args[2].toString() : 'js';

        final UrlVerdict verdict = switch (verdictName) {
          'external' => UrlVerdict.external,
          'redirect' => UrlVerdict.redirect,
          _ => UrlVerdict.block,
        };

        _log.addDeduplicated(
          url: url,
          verdict: verdict,
          reason: 'stopped inside the page',
          source: source,
        );

        if (verdict == UrlVerdict.redirect) {
          unawaited(_loadInbox());
        } else if (verdict == UrlVerdict.block) {
          _showBlockedNotice();
        }
        return null;
      },
    );

    // Reports from the in-page reel guard. This is the only signal that the
    // in-DM viewer exists, because it creates no URL and no history entry.
    controller.addJavaScriptHandler(
      handlerName: 'miReelState',
      callback: (List<dynamic> args) {
        final String state = args.isNotEmpty ? args[0].toString() : '';
        final String detail = args.length > 1 ? args[1].toString() : '';

        switch (state) {
          case 'open':
            if (mounted && !_reelOpen) setState(() => _reelOpen = true);
            break;
          case 'closed':
            if (mounted && _reelOpen) setState(() => _reelOpen = false);
            break;
          case 'blocked':
            _log.addDeduplicated(
              url: _currentUrl,
              verdict: UrlVerdict.block,
              reason: 'reel opened; mode B closed it ($detail)',
              source: 'reel',
            );
            _showReelUnavailable();
            unawaited(_closeReel());
            break;
          case 'freeze-failed':
            // Focus mode is best effort (SPEC §5.3). A freeze that cannot be
            // applied means we cannot promise "one reel", so leave.
            _log.addDeduplicated(
              url: _currentUrl,
              verdict: UrlVerdict.block,
              reason: 'reel freeze failed; leaving the viewer',
              source: 'reel',
            );
            _showReelUnavailable();
            unawaited(_closeReel());
            break;
        }
        return null;
      },
    );
  }

  /// Layer 1: every real page load passes through here.
  Future<NavigationActionPolicy?> _onNavigationRequest(
    InAppWebViewController controller,
    NavigationAction action,
  ) async {
    final WebUri? uri = action.request.url;
    if (uri == null) return NavigationActionPolicy.ALLOW;

    // Only the main frame can replace what the user is looking at. Blocking
    // subframes would break Instagram's embedded content (and possibly login)
    // without adding any protection: an iframe that navigates the top frame
    // comes back through here as a main-frame navigation.
    if (action.isForMainFrame == false) return NavigationActionPolicy.ALLOW;

    final UrlDecision decision = _policy.decide(uri);
    _log.addDeduplicated(
      url: uri.toString(),
      verdict: decision.verdict,
      reason: decision.reason,
      source: 'navigation',
    );

    switch (decision.verdict) {
      case UrlVerdict.allow:
        return NavigationActionPolicy.ALLOW;

      case UrlVerdict.redirect:
        final Uri? target = decision.target;
        if (target != null) {
          // Deferred: navigating from inside this callback is re-entrant.
          Future<void>.microtask(() => _loadUrl(target.toString()));
        }
        return NavigationActionPolicy.CANCEL;

      case UrlVerdict.block:
        _showBlockedNotice();
        return NavigationActionPolicy.CANCEL;

      case UrlVerdict.external:
        // Silent: handing off to another app is never desired, and the user did
        // not intend to leave the app anyway.
        return NavigationActionPolicy.CANCEL;
    }
  }

  /// Layer 2: backstop for client-side route changes that slipped past the
  /// in-page guard.
  void _onVisitedHistory(
    InAppWebViewController controller,
    WebUri? url,
    bool? isReload,
  ) {
    final String value = url?.toString() ?? '';
    if (value.isEmpty) return;

    _currentUrl = value;
    final UrlDecision decision = _policy.decide(Uri.parse(value));
    if (!decision.isBlocking && decision.verdict != UrlVerdict.redirect) return;

    _log.addDeduplicated(
      url: value,
      verdict: decision.verdict,
      reason: decision.reason,
      source: 'history',
    );

    if (!_isInbox(value)) {
      unawaited(_loadInbox());
    }
  }

  /// Layer 3 is the JavaScript guard; it reports through `miNavigationBlocked`.

  Future<void> _onLoadStop(
    InAppWebViewController controller,
    WebUri? url,
  ) async {
    final String value = url?.toString() ?? '';
    _currentUrl = value;
    if (mounted) {
      setState(() {
        _isLoading = false;
        _progress = 1;
        _failure = null;
        _failureDetail = null;
        // A completed navigation means any overlay from the previous page is
        // gone with the document.
        _reelOpen = false;
      });
    }

    // Last-resort guard: if a forbidden page somehow rendered, leave it.
    if (value.isEmpty) return;
    final UrlDecision decision = _policy.decide(Uri.parse(value));
    _log.addDeduplicated(
      url: value,
      verdict: decision.verdict,
      reason: decision.isBlocking
          ? 'loaded anyway; recovering'
          : decision.reason,
      source: 'load',
    );
    if (decision.isBlocking) {
      unawaited(_loadInbox());
      return;
    }

    // A login page after a DM page means the session ended. Instagram is free
    // to expose this as a redirect at any moment, so it is detected here rather
    // than by trying to predict it.
    if (_isLoginPage(value)) {
      if (_sawAuthenticatedPage && !_clearingSession) {
        _showExpiredNotice();
      }
      _sawAuthenticatedPage = false;
    } else {
      _sawAuthenticatedPage = true;
    }
  }

  void _onProgressChanged(InAppWebViewController controller, int progress) {
    if (!mounted) return;
    setState(() {
      _progress = (progress / 100).clamp(0, 1);
      _isLoading = progress < 100;
    });
  }

  void _onReceivedError(
    InAppWebViewController controller,
    WebResourceRequest request,
    WebResourceError error,
  ) {
    if (request.isForMainFrame != true) return;
    if (mounted) {
      setState(() {
        _failure = FailureKind.network;
        _failureDetail = error.description;
        _isLoading = false;
      });
    }
  }

  void _onReceivedHttpError(
    InAppWebViewController controller,
    WebResourceRequest request,
    WebResourceResponse response,
  ) {
    if (request.isForMainFrame != true) return;
    final int? status = response.statusCode;
    if (status == null || status < 500) return;
    if (mounted) {
      setState(() {
        _failure = FailureKind.server;
        _failureDetail = 'HTTP $status';
        _isLoading = false;
      });
    }
  }

  // ------------------------------------------------------------------ actions

  /// The app's own navigation path. Every internal load goes through the policy,
  /// so a programming mistake cannot open a blocked surface. Page-initiated
  /// navigation is handled separately by [_onNavigationRequest].
  Future<void> _loadUrl(String url) async {
    final InAppWebViewController? controller = _controller;
    if (controller == null) return;

    final UrlDecision decision = _policy.decide(Uri.parse(url));
    if (decision.verdict == UrlVerdict.redirect && decision.target != null) {
      return _loadUrl(decision.target.toString());
    }
    if (decision.isBlocking) {
      _log.addDeduplicated(
        url: url,
        verdict: decision.verdict,
        reason: 'refused an internal load: ${decision.reason}',
        source: 'internal',
      );
      return;
    }
    await controller.loadUrl(urlRequest: URLRequest(url: WebUri(url)));
  }

  Future<void> _loadInbox() => _loadUrl(InstagramRoutes.inbox.toString());

  /// Leaves the in-page reel viewer.
  ///
  /// The viewer exposes no URL and no close control we can depend on, so the
  /// reliable exit is to reload the page it is layered over. The guard freezes
  /// the next reel normally if the user opens another one.
  Future<void> _closeReel() async {
    if (mounted && _reelOpen) setState(() => _reelOpen = false);
    final InAppWebViewController? controller = _controller;
    if (controller == null) return;
    await controller.reload();
  }

  bool _isInbox(String url) {
    final String path = Uri.tryParse(url)?.path ?? '';
    return path == '/direct/inbox' || path == '/direct/inbox/';
  }

  bool _isLoginPage(String url) {
    final String path = Uri.tryParse(url)?.path ?? '';
    return path.startsWith('/accounts/login');
  }

  /// Tells the user a reel was refused. Used by Mode B and by a failed freeze.
  void _showReelUnavailable() {
    if (!mounted) return;
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text("Reels aren't available in this mode"),
          behavior: SnackBarBehavior.floating,
          duration: Duration(milliseconds: 2200),
        ),
      );
  }

  /// Explains a session that ended while the app was in use.
  void _showExpiredNotice() {
    if (!mounted) return;
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('Your session ended. Sign in again.'),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 4),
        ),
      );
  }

  void _showBlockedNotice() {
    final DateTime now = DateTime.now();
    if (_lastBlockNotice != null &&
        now.difference(_lastBlockNotice!) < const Duration(seconds: 2)) {
      return;
    }
    _lastBlockNotice = now;
    if (!mounted) return;
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('Not available in Minimal Instagram'),
          behavior: SnackBarBehavior.floating,
          duration: Duration(milliseconds: 1600),
        ),
      );
  }

  /// Android back: never exit from a deep page, never reveal a blocked surface.
  Future<void> _handleBack() async {
    // While a reel is open, back means "leave this reel", not "leave the thread".
    // The viewer has no history entry, so without this the user would be thrown
    // out of the conversation instead.
    if (_reelOpen) {
      await _closeReel();
      return;
    }

    final InAppWebViewController? controller = _controller;
    if (controller == null) {
      await SystemNavigator.pop();
      return;
    }

    final WebUri? url = await controller.getUrl();
    final String current = url?.toString() ?? '';
    if (!_isInbox(current) && await controller.canGoBack()) {
      await controller.goBack();
      return;
    }
    if (!_isInbox(current)) {
      await _loadInbox();
      return;
    }
    await SystemNavigator.pop();
  }

  void _retry() {
    setState(() {
      _failure = null;
      _failureDetail = null;
      _isLoading = true;
    });
    final InAppWebViewController? controller = _controller;
    if (controller == null) {
      unawaited(_loadGuardScript());
    } else {
      unawaited(controller.reload());
    }
  }

  Future<void> _openSettings() async {
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext context) => SettingsSheet(
        reelPolicy: widget.settings.reelPolicy,
        onReelPolicyChanged: (ReelPolicy policy) =>
            widget.settings.setBlockReels(policy == ReelPolicy.block),
        onClearSession: _clearSession,
        version: AppConfig.version,
      ),
    );
  }

  /// Deletes everything Instagram left on the device, then shows the login page.
  ///
  /// This is the only place the app touches the session. It deletes; it never
  /// reads. History and cache are cleared too, so the signed-in pages cannot be
  /// reached with the back button afterwards.
  Future<void> _clearSession() async {
    final InAppWebViewController? controller = _controller;
    _clearingSession = true;
    _sawAuthenticatedPage = false;

    try {
      await CookieManager.instance().deleteAllCookies();
      await WebStorageManager.instance().deleteAllData();
      if (controller != null) {
        await InAppWebViewController.clearAllCache(includeDiskFiles: true);
        await controller.clearHistory();
      }
      _log.add(
        url: InstagramRoutes.login.toString(),
        verdict: UrlVerdict.allow,
        reason: 'session cleared by user',
        source: 'session',
      );
    } catch (error) {
      // Never leave the user on a signed-in page because cleanup half failed.
      debugPrint('clear session failed: $error');
    }

    await _loadUrl(InstagramRoutes.login.toString());
    _clearingSession = false;
  }

  Future<void> _openDebug() async {
    final InAppWebViewController? controller = _controller;
    if (controller == null) return;
    final WebUri? url = await controller.getUrl();

    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => DebugScreen(
          controller: controller,
          policy: _policy,
          log: _log,
          currentUrl: url?.toString() ?? _currentUrl,
        ),
      ),
    );
    // The debug screen can navigate; resync the cached URL when it closes.
    final WebUri? after = await controller.getUrl();
    if (mounted) {
      setState(() => _currentUrl = after?.toString() ?? _currentUrl);
    }
  }

  // -------------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (!didPop) unawaited(_handleBack());
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: 'Back',
            icon: const Icon(Icons.arrow_back),
            onPressed: () => unawaited(_handleBack()),
          ),
          title: const Text('Messages'),
          actions: <Widget>[
            IconButton(
              tooltip: 'Settings',
              icon: const Icon(Icons.settings_outlined),
              onPressed: () => unawaited(_openSettings()),
            ),
            IconButton(
              tooltip: 'Reload',
              icon: const Icon(Icons.refresh),
              onPressed: () => unawaited(_controller?.reload()),
            ),
            if (kDebugMode)
              IconButton(
                tooltip: 'Debug',
                icon: const Icon(Icons.bug_report_outlined),
                onPressed: () => unawaited(_openDebug()),
              ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(2),
            child: _isLoading
                ? LinearProgressIndicator(
                    value: _progress > 0 && _progress < 1 ? _progress : null,
                    minHeight: 2,
                  )
                : const SizedBox(height: 2),
          ),
        ),
        body: Stack(
          children: <Widget>[
            if (_guardSource != null)
              InAppWebView(
                initialUrlRequest: URLRequest(
                  url: WebUri(AppConfig.startUrl.toString()),
                ),
                initialSettings: buildWebViewSettings(),
                initialUserScripts: UnmodifiableListView<UserScript>(
                  <UserScript>[
                    UserScript(
                      source: _guardSource!,
                      injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
                    ),
                  ],
                ),
                onWebViewCreated: _onWebViewCreated,
                shouldOverrideUrlLoading: _onNavigationRequest,
                onUpdateVisitedHistory: _onVisitedHistory,
                onLoadStop: _onLoadStop,
                onProgressChanged: _onProgressChanged,
                onReceivedError: _onReceivedError,
                onReceivedHttpError: _onReceivedHttpError,
              ),
            if (_guardSource == null)
              ColoredBox(
                color: Theme.of(context).colorScheme.surface,
                child: const Center(child: CircularProgressIndicator()),
              ),
            if (_failure != null)
              ErrorView(
                kind: _failure!,
                detail: _failureDetail,
                onRetry: _retry,
              ),
            if (_reelOpen && _policy.reelPolicy == ReelPolicy.allow)
              Positioned(
                left: 16,
                right: 16,
                bottom: 24,
                child: _ReelBanner(onClose: () => unawaited(_closeReel())),
              ),
          ],
        ),
      ),
    );
  }
}

/// The focus-mode banner shown over a single reel.
///
/// It exists so the user always has an exit that does not depend on Instagram's
/// own close button, which is not a public contract.
class _ReelBanner extends StatelessWidget {
  const _ReelBanner({required this.onClose});

  /// Leaves the viewer and returns to the thread.
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Material(
      elevation: 6,
      borderRadius: BorderRadius.circular(24),
      color: theme.colorScheme.surface.withValues(alpha: 0.94),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 6, 6),
        child: Row(
          children: <Widget>[
            Icon(
              Icons.filter_none_rounded,
              size: 18,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            const Expanded(child: Text('Single reel')),
            TextButton(onPressed: onClose, child: const Text('Close')),
          ],
        ),
      ),
    );
  }
}
