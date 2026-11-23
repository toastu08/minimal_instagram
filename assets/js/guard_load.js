// Load-time sanitizer and DOM instrumentation.
//
// Injected at document start, after the rule set and the CSS have been attached
// to `window`. Responsibilities:
//   1. Keep the cosmetic stylesheet present, even if React rewrites <head>.
//   2. Remove nodes that CSS cannot hide correctly (the removal list).
//   3. Expose `window.__miSanitizerReport()` so the debug screen can prove the
//      sanitizer is running and show which selectors matched.
//
// Selector ownership: the selectors are NOT written here. They come from
// `assets/css/hide_instagram_chrome.css`, which is parsed at report time. This
// keeps one source of truth and means an edit to the CSS shows up in the report
// automatically.
//
// Invariant: this script must never throw. A cosmetic failure is acceptable; a
// broken page is not. Every DOM access is guarded, every selector query is
// wrapped, and a failed selector reports a count of -1 instead of raising.

(function () {
  'use strict';

  if (window.__miSanitizerInstalled) return;
  window.__miSanitizerInstalled = true;

  var CONFIG = window.__MI_SANITIZER || {};
  // The navigation rules are on `window` (set by the Dart bundle). The guard
  // script keeps its own private copy; this module reads the global.
  var RULES = window.__MI_RULES || {};
  var STYLE_ID = 'mi-sanitizer';
  // Marks chrome hidden by `hideGlobalChrome`; also used by the debug report.
  var CHROME_FLAG = 'data-mi-chrome-hidden';

  // Nodes that must be *removed* rather than hidden. Empty in v1: everything
  // the sanitizer needs to do today is expressible in CSS. Add an entry here
  // only when hiding leaves a broken layout or an invisible click target.
  var REMOVALS = [];

  // ------------------------------------------------------------- stylesheet

  function ensureStyle() {
    try {
      if (document.getElementById(STYLE_ID)) return;
      var target = document.head || document.documentElement;
      if (!target) return;
      var style = document.createElement('style');
      style.id = STYLE_ID;
      style.textContent = CONFIG.css || '';
      target.appendChild(style);
    } catch (e) {
      /* cosmetic only; the URL guard is unaffected */
    }
  }

  // ---------------------------------------------------------------- removals

  function applyRemovals(root) {
    if (!REMOVALS.length) return;
    var scope = root || document;
    for (var i = 0; i < REMOVALS.length; i++) {
      try {
        var nodes = scope.querySelectorAll(REMOVALS[i]);
        for (var j = 0; j < nodes.length; j++) {
          var node = nodes[j];
          if (node && node.parentNode) node.parentNode.removeChild(node);
        }
      } catch (e) {
        /* a selector that stops matching is not an error */
      }
    }
  }

  // ---------------------------------------------------------------- reporting

  // Extracts the selector of every rule in the stylesheet, in file order.
  // Comments and at-rules are skipped; grouped selectors are split.
  function cssSelectors(css) {
    var selectors = [];
    var text = String(css || '').replace(/\/\*[\s\S]*?\*\//g, '');
    var rule = /([^{}]+)\{/g;
    var match;
    while ((match = rule.exec(text)) !== null) {
      var group = match[1].trim();
      if (!group || group.charAt(0) === '@') continue;
      var parts = group.split(',');
      for (var i = 0; i < parts.length; i++) {
        var selector = parts[i].trim();
        if (selector) selectors.push(selector);
      }
    }
    return selectors;
  }

  function report() {
    var selectors = cssSelectors(CONFIG.css);
    var rules = [];
    for (var i = 0; i < selectors.length; i++) {
      var count;
      try {
        count = document.querySelectorAll(selectors[i]).length;
      } catch (e) {
        // -1 means "invalid selector", which is a bug in the CSS file rather
        // than a page change. Surface it instead of hiding it.
        count = -1;
      }
      rules.push({ selector: selectors[i], count: count });
    }
    return {
      version: CONFIG.version || '?',
      url: String(window.location.href),
      styleInjected: !!document.getElementById(STYLE_ID),
      rules: rules,
      removals: REMOVALS.slice(),
      chromeHidden: document.querySelectorAll('[' + CHROME_FLAG + ']').length
    };
  }

  // ------------------------------------------------------------------ wiring

  // Instagram mutates the DOM continuously, so re-checks are debounced.
  var pendingNodes = [];
  var flushTimer = null;

  function flush() {
    flushTimer = null;
    ensureStyle();
    var batch = pendingNodes;
    pendingNodes = [];
    for (var i = 0; i < batch.length; i++) {
      applyRemovals(batch[i]);
    }
    hideGlobalChrome();
    escapeSignupSurface();
  }

  function onMutations(mutations) {
    try {
      for (var i = 0; i < mutations.length; i++) {
        var added = mutations[i].addedNodes;
        for (var j = 0; j < added.length; j++) {
          if (added[j].nodeType === 1) pendingNodes.push(added[j]);
        }
      }
      if (flushTimer === null) flushTimer = setTimeout(flush, 250);
    } catch (e) {
      /* never let observation break the page */
    }
  }

  function observe() {
    try {
      if (window.__miSanitizerObserver) return;
      var Observer = window.MutationObserver || window.WebKitMutationObserver;
      if (!Observer || !document.documentElement) return;
      window.__miSanitizerObserver = new Observer(onMutations);
      window.__miSanitizerObserver.observe(document.documentElement, {
        childList: true,
        subtree: true
      });
    } catch (e) {
      /* observation is an optimization, not a requirement */
    }
  }

  ensureStyle();
  applyRemovals(document);
  hideGlobalChrome();
  escapeSignupSurface();
  observe();

  document.addEventListener('DOMContentLoaded', function () {
    ensureStyle();
    applyRemovals(document);
    hideGlobalChrome();
    escapeSignupSurface();
    observe();
  });

  // A bfcache restore keeps the old document; make sure the style survived.
  window.addEventListener('pageshow', function () {
    ensureStyle();
    applyRemovals(document);
    hideGlobalChrome();
    escapeSignupSurface();
  });

  // Instagram can swap chrome without adding a node the observer sees. The
  // chrome check is two small queries; the sign-up check runs more often because
  // it is the only defense against a surface with no URL.
  setInterval(hideGlobalChrome, 1500);
  setInterval(escapeSignupSurface, 500);

  window.__miSanitizerReport = report;

  // ------------------------------------------------------------ global chrome
  //
  // The standalone post page (`/p/<code>/`) renders Instagram's global bottom
  // tab bar (Home / Explore / Reels / Messages) and a "Use the app" install
  // banner. Neither has a semantic attribute the stylesheet could target, and a
  // `:has()` selector would match ancestors all the way up to <body>, hiding the
  // whole app. They are therefore hidden structurally: find a known link or
  // label, walk up to its fixed-position wrapper, hide that wrapper.
  //
  // Purely cosmetic. If Instagram restructures these nodes, nothing is hidden and
  // the page still works; UrlPolicy still refuses every destination.

  function fixedAncestor(start, maxHeight) {
    var el = start;
    for (var depth = 0; el && el !== document.body && depth < 12; depth++) {
      try {
        if (window.getComputedStyle(el).position === 'fixed') {
          var rect = el.getBoundingClientRect();
          if (rect.height > 0 && rect.height <= maxHeight) return el;
        }
      } catch (e) { /* detached while walking */ }
      el = el.parentElement;
    }
    return null;
  }

  function hideChromeNode(node) {
    if (!node || node.nodeType !== 1) return;
    try {
      node.setAttribute(CHROME_FLAG, '1');
      node.style.setProperty('display', 'none', 'important');
    } catch (e) { /* detached mid-iteration */ }
  }

  function hideGlobalChrome() {
    try {
      // The tab bar is the fixed wrapper around links to blocked feed routes.
      // DM pages have no /explore/ or /reels/ links, so this never touches the
      // DM top bar.
      var links = document.querySelectorAll(
        'a[href="/explore/"], a[href="/reels/"]'
      );
      for (var i = 0; i < links.length; i++) {
        var bar = fixedAncestor(links[i], 180);
        if (bar) hideChromeNode(bar);
      }

      // The install banner is a button whose whole label is the prompt. Once its
      // wrapper is hidden the button measures zero height, so check for an
      // already-hidden ancestor instead of hiding the button a second time.
      var buttons = document.querySelectorAll('button');
      for (var j = 0; j < buttons.length; j++) {
        if ((buttons[j].textContent || '').trim() !== 'Use the app') continue;
        if (buttons[j].closest('[' + CHROME_FLAG + ']')) continue;
        hideChromeNode(fixedAncestor(buttons[j], 220) || buttons[j]);
      }
    } catch (e) { /* cosmetic only */ }
  }

  // ------------------------------------------------------- client-side surfaces
  //
  // Instagram renders its sign-up flow *inside* the login page: the URL never
  // changes, history does not change, and no navigation callback fires
  // (verified 2026-11-23). UrlPolicy therefore cannot see it at all.
  //
  // The document-start guard refuses the visible entry controls. This is the
  // backstop for any other way in (programmatic click, a restyled control, a
  // future entry point): on the login page, if the sign-up markers appear,
  // reload. Reloading the login URL is an allowed navigation and returns the
  // sign-in form. Sign-up is out of scope (SPEC §4.5).
  var SIGNUP_MARKERS =
    'input[type="tel"][aria-label="Mobile Number"], ' +
    'button[aria-label="Sign up with email"]';
  var lastSurfaceEscape = 0;

  function reportSurface(route) {
    try {
      if (window.flutter_inappwebview &&
          window.flutter_inappwebview.callHandler) {
        window.flutter_inappwebview.callHandler(
          'miNavigationBlocked', route, 'block', 'surface'
        );
      }
    } catch (e) { /* the bridge can die on navigation */ }
  }

  function escapeSignupSurface() {
    try {
      if (!/^\/accounts\/login/.test(window.location.pathname)) return;
      if (!document.querySelector(SIGNUP_MARKERS)) return;

      var now = Date.now();
      // One reload per 5 s is enough; do not fight the page in a loop.
      if (now - lastSurfaceEscape < 5000) return;
      lastSurfaceEscape = now;
      console.warn('[mi-guard] sign-up surface rendered without a URL; reloading login');
      reportSurface('/accounts/emailsignup/');
      window.location.reload();
    } catch (e) { /* never break the page */ }
  }

  // --------------------------------------------------------------- reel guard
  //
  // Why this is structural (see PROGRESS.md §2.5): the in-DM reel viewer is a
  // client-side overlay. It produces no URL, no history entry, no dialog role
  // and no permalink. It can only be recognised from the DOM, and the only
  // durable defense is to remove the neighbouring slides so there is nothing to
  // scroll to, then freeze the container.
  //
  // Detection: a <video> that fills most of the viewport and intersects it. The
  // carousel mounts three videos at once, stacked in one scroll container; the
  // off-screen ones have no viewport intersection.
  //
  // Best effort, never a guarantee. Mode B (reels fully blocked) exists for
  // exactly this reason and is selected by the policy in `__MI_RULES`.

  var REEL = {
    open: false,
    video: null,
    container: null,
    scroller: null,
    hidden: [],
    blockedReported: false,
    lastDetail: 'none',
    gestureHost: null,
    failedSince: 0,
    freezeFailureReported: false
  };

  var reelQueue = [];
  var REEL_HANDLER = 'miReelState';

  function reelBridgeReady() {
    return !!(window.flutter_inappwebview &&
              window.flutter_inappwebview.callHandler);
  }

  function reelReport(state, detail) {
    REEL.lastDetail = detail || '';
    var payload = [state, detail || ''];
    if (reelBridgeReady()) {
      try {
        window.flutter_inappwebview.callHandler(
          REEL_HANDLER, payload[0], payload[1]
        );
        return;
      } catch (e) { /* fall through to the queue */ }
    }
    if (reelQueue.length < 20) reelQueue.push(payload);
  }

  function flushReelQueue() {
    if (!reelBridgeReady() || reelQueue.length === 0) return;
    var queued = reelQueue;
    reelQueue = [];
    for (var i = 0; i < queued.length; i++) {
      try {
        window.flutter_inappwebview.callHandler(
          REEL_HANDLER, queued[i][0], queued[i][1]
        );
      } catch (e) { /* the bridge can die on navigation */ }
    }
  }

  window.addEventListener('flutterInAppWebViewPlatformReady', flushReelQueue);
  setInterval(flushReelQueue, 500);

  function visibleVideo() {
    var vpW = window.innerWidth || 0;
    var vpH = window.innerHeight || 0;
    if (vpW === 0 || vpH === 0) return null;

    var videos = document.querySelectorAll('video');
    var fallback = null;
    for (var i = 0; i < videos.length; i++) {
      var video = videos[i];
      var rect = video.getBoundingClientRect();
      if (rect.width < vpW * 0.6 || rect.height < vpH * 0.5) continue;
      if (rect.bottom < 40 || rect.top > vpH - 40) continue;
      if (!video.paused) return video;
      if (!fallback) fallback = video;
    }
    return fallback;
  }

  function scrollableAncestor(video) {
    var el = video.parentElement;
    while (el && el !== document.body && el !== document.documentElement) {
      try {
        var style = window.getComputedStyle(el);
        var scrolls = style.overflowY === 'auto' || style.overflowY === 'scroll';
        if (scrolls && el.scrollHeight > el.clientHeight + 100) return el;
      } catch (e) { /* detached or styled oddly */ }
      el = el.parentElement;
    }
    return null;
  }

  // Finds the level whose children are the slides.
  //
  // Usually this is the scroller itself. If the scroller wraps a single
  // container, descend through single-child wrappers until a level with more
  // than one child appears. This avoids hiding overlays that are siblings of the
  // carousel rather than slides inside it.
  function slideContainer(scroller, video) {
    var el = scroller;
    for (var depth = 0; depth < 8 && el && el !== video; depth++) {
      var kids = [];
      for (var i = 0; i < el.children.length; i++) kids.push(el.children[i]);
      if (kids.length > 1) return el;

      var next = null;
      for (var j = 0; j < kids.length; j++) {
        if (kids[j].contains(video) || kids[j] === video) {
          next = kids[j];
          break;
        }
      }
      if (!next || next === el) break;
      el = next;
    }
    return el;
  }

  function hideSlide(node) {
    if (!node || node.nodeType !== 1) return;
    try {
      if (!node.hasAttribute('data-mi-reel-hidden')) {
        node.setAttribute('data-mi-reel-hidden', '1');
        node.style.setProperty('display', 'none', 'important');
        REEL.hidden.push(node);
      }
    } catch (e) { /* a node may disappear mid-iteration */ }
  }

  function freezeContainer(scroller) {
    try {
      scroller.setAttribute('data-mi-reel-frozen', '1');
      scroller.style.setProperty('overflow', 'hidden', 'important');
      scroller.style.setProperty('touch-action', 'none', 'important');
      scroller.style.setProperty('overscroll-behavior', 'contain', 'important');
      if (!scroller.__miTouchGuard) {
        var prevent = function (event) {
          if (event.cancelable) event.preventDefault();
        };
        scroller.addEventListener('touchmove', prevent, { passive: false });
        scroller.__miTouchGuard = prevent;
      }
    } catch (e) { /* cosmetic freeze only */ }
  }

  // Instagram also listens for swipe gestures on document-level overlays (reply
  // bar, action rail). Blocking only a carousel let a swipe close the viewer
  // instead of advancing, which looks like a crash. Taps still work: only
  // movement is cancelled.
  //
  // This runs even when no carousel was found, because a viewer that mounts a
  // single video has no scroll container at all and is still dismissible by
  // swipe (observed on 2026-11-18). The URL cannot see any of this.
  function blockGestures(host) {
    try {
      if (host) {
        host.setAttribute('data-mi-reel-frozen', '1');
        host.style.setProperty('touch-action', 'none', 'important');
        host.style.setProperty('overscroll-behavior', 'contain', 'important');
        REEL.gestureHost = host;
      }
      if (!document.__miReelTouchGuard) {
        var documentPrevent = function (event) {
          if (event.cancelable) event.preventDefault();
        };
        document.addEventListener('touchmove', documentPrevent, {
          passive: false,
          capture: true
        });
        document.__miReelTouchGuard = documentPrevent;
      }
    } catch (e) { /* cosmetic freeze only */ }
  }

  function applyReelFreeze() {
    var video = visibleVideo();
    if (!video) return 'no-video';

    var scroller = scrollableAncestor(video);
    var container = null;

    if (scroller) {
      container = slideContainer(scroller, video);
      if (!container) return 'no-container';
    } else {
      // One video, nothing to collapse. Freeze gestures on its own box.
      container = video.parentElement;
      if (!container) return 'no-container';
    }

    // If the viewer replaced its playing slide, release the old one first.
    if (REEL.container && REEL.container !== container) releaseReelFreeze(false);

    REEL.video = video;
    REEL.scroller = scroller;
    REEL.container = container;

    if (scroller) {
      for (var i = 0; i < container.children.length; i++) {
        var child = container.children[i];
        if (child === video || child.contains(video)) continue;
        hideSlide(child);
      }
      freezeContainer(scroller);
    }

    blockGestures(container);
    return scroller ? 'ok' : 'single';
  }

  function releaseReelFreeze(reportClose) {
    for (var i = 0; i < REEL.hidden.length; i++) {
      var node = REEL.hidden[i];
      try {
        node.style.removeProperty('display');
        node.removeAttribute('data-mi-reel-hidden');
      } catch (e) { /* already detached */ }
    }
    REEL.hidden = [];

    try {
      if (REEL.scroller) {
        REEL.scroller.removeAttribute('data-mi-reel-frozen');
        REEL.scroller.style.removeProperty('overflow');
        REEL.scroller.style.removeProperty('touch-action');
        REEL.scroller.style.removeProperty('overscroll-behavior');
        if (REEL.scroller.__miTouchGuard) {
          REEL.scroller.removeEventListener(
            'touchmove', REEL.scroller.__miTouchGuard, false
          );
          REEL.scroller.__miTouchGuard = null;
        }
      }
      if (document.__miReelTouchGuard) {
        document.removeEventListener(
          'touchmove', document.__miReelTouchGuard, true
        );
        document.__miReelTouchGuard = null;
      }
      if (REEL.gestureHost) {
        REEL.gestureHost.removeAttribute('data-mi-reel-frozen');
        REEL.gestureHost.style.removeProperty('touch-action');
        REEL.gestureHost.style.removeProperty('overscroll-behavior');
        REEL.gestureHost = null;
      }
    } catch (e) { /* detached */ }

    REEL.open = false;
    REEL.video = null;
    REEL.scroller = null;
    REEL.container = null;
    REEL.blockedReported = false;
    REEL.failedSince = 0;
    REEL.freezeFailureReported = false;

    if (reportClose) reelReport('closed', 'viewer left the DOM');
  }

  function reelTick() {
    try {
      var blocked = RULES.reelPolicy === 'block';

      if (blocked) {
        if (visibleVideo()) {
          if (!REEL.blockedReported) {
            REEL.blockedReported = true;
            REEL.open = true;
            reelReport('blocked', 'policy: block');
          }
        } else if (REEL.open) {
          releaseReelFreeze(true);
        }
        return;
      }

      var video = visibleVideo();
      if (!video) {
        if (REEL.open) releaseReelFreeze(true);
        return;
      }

      var result = applyReelFreeze();
      var frozen = result === 'ok' || result === 'single';
      if (!REEL.open) {
        REEL.open = true;
        REEL.failedSince = 0;
        REEL.freezeFailureReported = false;
        reelReport('open', result);
      }

      if (frozen) {
        REEL.failedSince = 0;
        REEL.freezeFailureReported = false;
      } else {
        // Give Instagram a moment to finish mounting before declaring failure:
        // a transient failure while the carousel is being built is normal.
        if (!REEL.failedSince) REEL.failedSince = Date.now();
        if (!REEL.freezeFailureReported &&
            Date.now() - REEL.failedSince > 2000) {
          REEL.freezeFailureReported = true;
          reelReport('freeze-failed', 'no freeze for 2s');
          try {
            console.warn('[mi-reel] ' + JSON.stringify(reelDiagnostics()));
          } catch (logError) { /* logging must not throw either */ }
        }
      }
    } catch (e) {
      /* the reel guard must never break the page */
    }
  }

  setInterval(reelTick, 600);
  document.addEventListener('DOMContentLoaded', reelTick);

  // Diagnostics for the debug screen and for failure logs. Read-only.
  function reelDiagnostics() {
    function rectOf(video) {
      var r = video.getBoundingClientRect();
      return {
        w: Math.round(r.width),
        h: Math.round(r.height),
        top: Math.round(r.top),
        bottom: Math.round(r.bottom),
        paused: !!video.paused
      };
    }

    var videos = [];
    var nodes = document.querySelectorAll('video');
    for (var i = 0; i < nodes.length; i++) videos.push(rectOf(nodes[i]));

    var ancestors = [];
    var active = visibleVideo() || nodes[0];
    var el = active && active.parentElement;
    for (var depth = 0; el && depth < 12; depth++) {
      try {
        var style = window.getComputedStyle(el);
        ancestors.push({
          tag: el.tagName,
          overflowY: style.overflowY,
          clientHeight: el.clientHeight,
          scrollHeight: el.scrollHeight
        });
      } catch (e) {
        ancestors.push({ tag: el.tagName, error: String(e) });
      }
      el = el.parentElement;
    }

    return {
      policy: RULES.reelPolicy,
      open: REEL.open,
      detail: REEL.lastDetail,
      hiddenSlides: REEL.hidden.length,
      hasVideo: !!visibleVideo(),
      frozen: !!document.__miReelTouchGuard,
      videos: videos,
      ancestors: ancestors
    };
  }

  window.__miReelState = reelDiagnostics;
})();
