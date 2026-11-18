// Document-start navigation guard.
//
// Injected into the page before Instagram's own scripts run, at
// AT_DOCUMENT_START. Its only job is to stop disallowed navigation *inside* the
// page, where the native webview callbacks cannot see it.
//
// Why this exists (see PROGRESS.md §2.4): Instagram is a single-page app. Opening
// a conversation, a profile or a blocked surface is a `history.pushState` call,
// not a page load. Conversation rows are not even anchors, so click interception
// alone would miss them.
//
// Three things are enforced here:
//   1. `history.pushState` / `replaceState` are wrapped and vetoed.
//   2. Anchor clicks are inspected in the capture phase, before React sees them.
//   3. `window.open` is denied outright.
//
// The rules are NOT written here. They are generated from `UrlPolicy` in Dart
// and injected as `window.__MI_RULES` immediately before this file. Editing a
// rule list in this file would break the single-source-of-truth guarantee.
//
// Invariant: this script must never throw. A navigation guard that breaks the
// page is worse than no guard, because the user cannot reach their messages.

(function () {
  'use strict';

  if (window.__miGuardInstalled) return;
  window.__miGuardInstalled = true;

  var RULES = window.__MI_RULES || {};
  var HANDLER = 'miNavigationBlocked';

  var allowedPaths = RULES.allowedPaths || [];
  var hosts = RULES.hosts || [];
  var threadRe = new RegExp(RULES.threadPattern || '^$');
  var reelRe = new RegExp(RULES.reelPattern || '^$');
  var postRe = new RegExp(RULES.postPattern || '^$');
  var challengePrefix = RULES.challengePrefix || '/challenge';
  var inbox = RULES.inbox || 'https://www.instagram.com/direct/inbox/';

  // ---------------------------------------------------------------- decisions

  function normalizePath(path) {
    if (!path || path === '/') return '/';
    var out = path;
    while (out.length > 1 && out.charAt(out.length - 1) === '/') {
      out = out.slice(0, -1);
    }
    return out;
  }

  // Mirrors UrlPolicy.decide(). Returns 'allow', 'block', 'external' or
  // 'redirect'. When the two disagree, UrlPolicy is correct and this is a bug.
  function decide(rawUrl) {
    var u;
    try {
      u = new URL(rawUrl, window.location.href);
    } catch (e) {
      return 'block';
    }

    if (u.protocol !== 'http:' && u.protocol !== 'https:') return 'external';
    if (hosts.indexOf(u.hostname) === -1) return 'block';
    if (u.port && u.port !== '80' && u.port !== '443') return 'block';

    var path = normalizePath(u.pathname);

    if (path === '/' || path === '/direct') return 'redirect';
    if (allowedPaths.indexOf(path) !== -1) return 'allow';
    if (threadRe.test(path)) return 'allow';
    if (path === challengePrefix || path.indexOf(challengePrefix + '/') === 0) {
      return 'allow';
    }
    if (RULES.reelPolicy === 'allow' && reelRe.test(path)) return 'allow';
    if (postRe.test(path)) return 'allow';

    return 'block';
  }

  // ----------------------------------------------------------------- reporting

  var pending = [];

  function bridgeReady() {
    return !!(window.flutter_inappwebview &&
              window.flutter_inappwebview.callHandler);
  }

  function flushPending() {
    if (!bridgeReady()) return;
    var queued = pending;
    pending = [];
    for (var i = 0; i < queued.length; i++) {
      try {
        window.flutter_inappwebview.callHandler(
          HANDLER, queued[i].url, queued[i].verdict, queued[i].source
        );
      } catch (e) { /* the bridge can die on navigation; ignore */ }
    }
  }

  function report(url, verdict, source) {
    var absolute;
    try {
      absolute = new URL(url, window.location.href).href;
    } catch (e) {
      absolute = String(url);
    }
    if (bridgeReady()) {
      try {
        window.flutter_inappwebview.callHandler(HANDLER, absolute, verdict, source);
        return;
      } catch (e) { /* fall through to the queue */ }
    }
    if (pending.length < 40) {
      pending.push({ url: absolute, verdict: verdict, source: source });
    }
  }

  window.addEventListener('flutterInAppWebViewPlatformReady', flushPending);
  // Flush opportunistically; the bridge attaches a moment after the page starts.
  var flushTimer = setInterval(function () {
    if (pending.length === 0) return;
    flushPending();
  }, 500);

  // --------------------------------------------------------------- the guard

  // Vetoing a pushState leaves the DOM untouched, so there is nothing to undo.
  function guardHistory() {
    var methods = ['pushState', 'replaceState'];
    for (var i = 0; i < methods.length; i++) {
      (function (name) {
        var original = window.history[name];
        if (!original || original.__miWrapped) return;

        var wrapped = function (state, title, url) {
          // A pushState with no URL only changes React's state; allow it.
          if (url === undefined || url === null) {
            return original.apply(this, arguments);
          }
          var verdict = decide(url);
          if (verdict === 'allow') {
            return original.apply(this, arguments);
          }
          report(url, verdict, 'history');
          return undefined;
        };
        wrapped.__miWrapped = true;
        try {
          window.history[name] = wrapped;
        } catch (e) { /* some engines freeze history; the native guard remains */ }
      })(methods[i]);
    }
  }

  guardHistory();
  window.addEventListener('pageshow', guardHistory);
  // Instagram occasionally swaps the history implementation during hydration.
  setInterval(guardHistory, 1000);

  // Capture-phase click interception: React never sees a blocked click.
  document.addEventListener('click', function (event) {
    var el = event.target;
    while (el && el !== document && el.tagName !== 'A') {
      el = el.parentElement;
    }
    if (!el || el.tagName !== 'A') return;

    var href = el.getAttribute('href');
    if (!href || href.charAt(0) === '#') return;
    // `javascript:` hrefs are inline handlers that happen to look like links.
    // Blocking them would break Instagram's own buttons.
    if (href.indexOf('javascript:') === 0) return;

    var verdict = decide(href);
    if (verdict === 'allow') return;

    event.preventDefault();
    event.stopPropagation();
    report(href, verdict, 'click');
  }, true);

  // New windows are never part of this app.
  window.open = function () {
    report(window.location.href + '#window.open', 'block', 'popup');
    return null;
  };

  // Expose a tiny hook so the Flutter debug screen can ask the page what it
  // would do with a URL, without duplicating the rules in Dart test code.
  window.__miDecide = decide;
  window.__miInbox = inbox;
})();
