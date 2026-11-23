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
  var ports = RULES.ports || [80, 443];
  var threadRe = new RegExp(RULES.threadPattern || '^$');
  var reelRe = new RegExp(RULES.reelPattern || '^$');
  var postRe = new RegExp(RULES.postPattern || '^$');
  var challengePrefix = RULES.challengePrefix || '/challenge';
  var authPlatformPrefix = RULES.authPlatformPrefix || '/auth_platform';
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
    if (u.port && ports.indexOf(Number(u.port)) === -1) return 'block';

    var path = normalizePath(u.pathname);

    if (path === '/' || path === '/direct') return 'redirect';
    if (allowedPaths.indexOf(path) !== -1) return 'allow';
    if (threadRe.test(path)) return 'allow';
    if (path === challengePrefix || path.indexOf(challengePrefix + '/') === 0) {
      return 'allow';
    }
    if (path === authPlatformPrefix ||
        path.indexOf(authPlatformPrefix + '/') === 0) {
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
    // Mirror to the browser console so `adb logcat -s chromium` shows the same
    // decision the bridge sends to Dart. Useful when the bridge is not ready or
    // the page navigates before the report is delivered.
    try {
      console.warn('[mi-guard] ' + source + ' ' + verdict + ' ' + absolute);
    } catch (e) { /* never let logging break the guard */ }
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

  // Labels of Instagram controls that open a surface this app must not show.
  // Matched against `aria-label` first, then the element's own short text, both
  // case-insensitively and exactly. Kept deliberately small: a broad text match
  // would break ordinary buttons such as Follow or Send.
  //
  // Sign-up is the only observed case. It is rendered client-side on the login
  // page with no URL, so the URL rules cannot stop it (2026-11-23).
  var FORBIDDEN_LABELS = [
    'create new account',
    'create account',
    'sign up',
    'sign up with email'
  ];

  function controlLabel(el) {
    var aria = el.getAttribute && el.getAttribute('aria-label');
    if (aria) return aria.trim().toLowerCase();
    var text = (el.textContent || '').trim().toLowerCase();
    return text.length > 0 && text.length <= 40 ? text : '';
  }

  // Walks up from the click target to the nearest button-like control and
  // returns it when its label is forbidden. The observed sign-up control sits
  // seven levels above the span that receives the tap, so the walk must be deep
  // enough; 12 is cheap and still bounded.
  function forbiddenControl(target) {
    var el = target;
    for (var depth = 0; el && el !== document && depth < 12; depth++) {
      if (el.nodeType === 1) {
        var tag = el.tagName;
        var role = el.getAttribute('role');
        if (tag === 'BUTTON' || tag === 'A' || role === 'button') {
          var label = controlLabel(el);
          if (label && FORBIDDEN_LABELS.indexOf(label) !== -1) return el;
        }
      }
      el = el.parentElement;
    }
    return null;
  }

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
    // Instagram renders some surfaces with a `div[role="button"]` and a React
    // handler; the URL never changes. The observed case is the sign-up entry on
    // the login page ("Create new account", 2026-11-23). URLPolicy cannot see
    // it, so the control itself is refused before React's handler runs.
    var forbidden = forbiddenControl(event.target);
    if (forbidden) {
      event.preventDefault();
      event.stopImmediatePropagation();
      report('/accounts/emailsignup/', 'block', 'surface');
      return;
    }

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

  // Keyboard activation reaches a `role="button"` div without a click event.
  document.addEventListener('keydown', function (event) {
    if (event.key !== 'Enter' && event.key !== ' ') return;
    var forbidden = forbiddenControl(event.target);
    if (!forbidden) return;
    event.preventDefault();
    event.stopImmediatePropagation();
    report('/accounts/emailsignup/', 'block', 'surface');
  }, true);

  // Some BLOKS controls act on a press event handled at window level, which
  // runs before a document-level capture listener. Refuse the press on `window`
  // so the surface never renders; the backstop in guard_load.js covers anything
  // that still slips through.
  var PRESS_EVENTS = [
    'pointerdown', 'pointerup',
    'mousedown', 'mouseup',
    'touchstart', 'touchend'
  ];
  function blockForbiddenPress(event) {
    var forbidden = forbiddenControl(event.target);
    if (!forbidden) return;
    if (event.cancelable) event.preventDefault();
    event.stopImmediatePropagation();
    report('/accounts/emailsignup/', 'block', 'surface');
  }
  for (var p = 0; p < PRESS_EVENTS.length; p++) {
    window.addEventListener(PRESS_EVENTS[p], blockForbiddenPress, true);
  }

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
