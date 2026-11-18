# PROGRESS.md

State of the project for whoever picks this up next. Read this first, then
`SPEC.md` for intended behavior and `AGENTS.md` for rules.

**Last updated:** 2026-11-18
**Current milestone:** M5 implemented and verified in Mode A and Mode B; three
manual items remain (§11)
**Next action:** finish the M5 leftovers (§11: post view, keyboard "next",
focus-mode recovery), then M6 (persisted settings, About/version, release
manifest, release build). See the status board.

---

## Status board

| Milestone | Status | Notes |
| --- | --- | --- |
| M0 Feasibility spike | **Done** | Findings below. Spike code deleted in M1 |
| M1 Skeleton + pure core | **Done** | `UrlPolicy`, `InstagramRoutes`, app shell, 65 tests |
| M2 Enforcement | **Done** | Three layers live; verified on device, see §9 |
| M3 Sanitizer | **Done** | Small v1: hides the new-message pencil; report in debug. See §10 |
| M4 Login + session | **Done except one destructive test** | Settings, clear-session control, expiry notice, 3 widget tests. The actual sign-out has not been executed (would block reel testing). See §11 |
| M5 Single-item focus | **Done in Mode A and B** | Reel guard verified on device, 3 checklist items pending. See §11 |
| M6 Settings/debug | Not started | Persisted reels toggle, About/version, release manifest, release smoke test |
| M7 Regression tests | Not started | |

---

## 1. Environment facts

| Thing | Value |
| --- | --- |
| Flutter | 3.47.7, Dart 3.13.5 |
| Device | `emulator-5554`, Pixel-class, Android 17 / API 37, x86_64 |
| App id | `com.example.minimal_instagram` |
| Viewport observed | 411 × 862 logical px, portrait |

### Dependency decision: `flutter_inappwebview` is pinned to a beta

`6.2.0-beta.3` is pinned **deliberately**, with an exact version, not a caret.

Reason: the 6.1.x stable line cannot build under the AGP 9.1.0 toolchain that
Flutter 3.47's Android template generates. Its `build.gradle` references
`proguard-android.txt`, which AGP 9 rejects outright:

```
`getDefaultProguardFile('proguard-android.txt')` is no longer supported
```

`6.2.0-beta.3` switched to `proguard-android-optimize.txt` and
`flutter.compileSdkVersion`, and builds cleanly. It is the only release that
works. Revisit when a 6.2.x stable ships; the pin must not float upward on its
own.

### Toolchain gotcha

`adb` is not on `PATH`. Use `/home/toastu/Android/Sdk/platform-tools/adb`.

---

## 2. M0 spike results

The spike was a single-screen WebView that logged every navigation and dumped
the live DOM as JSONL to the app's `code_cache` directory.

**Read the raw data with:**

```bash
adb shell run-as com.example.minimal_instagram cat code_cache/mi_spike.jsonl
```

### 2.1 Login works, and it takes a detour

Confirmed on a real account with 2FA enabled. The actual navigation sequence was:

```
/accounts/login/
  → /auth_platform/?apc=<long token>
  → /auth_platform/codeentry/?apc=<long token>     <- 2FA code entry
  → /?deoia=1
  → /direct/inbox/
```

Consequences for `UrlPolicy`:

- `/auth_platform/` and `/auth_platform/codeentry/` **must** be allowed. Without
  them, two-factor login is impossible.
- The post-login landing is `/` with a `?deoia=1` query parameter. The `/`
  redirect rule must match on **path only**, ignoring query and fragment.
- `next`-style redirect parameters may appear on `/accounts/login/`; strip them
  when deciding, they do not change the route.

The login form is three inputs: `name=username`, `name=password`, and a cookie
consent checkbox. A plain password login is possible; no native form is needed
and none may be added.

### 2.2 Instagram's DOM has almost no semantic HTML

| Page | `nav` | `header` | `main` | `form` | `section` |
| --- | --- | --- | --- | --- | --- |
| Login | 0 | 0 | 0 | 0 | 0 |
| DM inbox | 0 | 0 | 0 | 0 | 1 |
| DM thread | 0 | 0 | 0 | 0 | 1 |
| Feed | 1 | 1 | 1 | 2 | 1 |

Everything is `<div>` with `role`/`aria-label` and generated class names
(`x1i10hfl`, `x78zum5`, …). **Generated classes must never be used as
selectors.** They are content-hashed and change on every deploy.

### 2.3 DM pages have no global navigation

This is the single biggest simplification in the project.

- The feed page has a `nav` with `[role=tablist]` and anchors for `/`,
  `/explore/`, `/reels/`, `/direct/` — that is the bottom nav bar.
- The DM inbox and DM thread have **no global nav**. They are already
  full-screen DM interfaces.
- Do **not** hide `[role=navigation]` generically. On a DM page that element is
  Instagram's own DM top bar (`Back`, `New message`, `Search`). Hiding it breaks
  the app.

Practical result: M3's sanitizer is much smaller than `SPEC.md` originally
assumed. Since the app never shows the feed, the bottom nav never renders in the
first place.

### 2.4 DM structure as observed

**Inbox** (`/direct/inbox/`):

- `div[role=navigation]` = DM top bar
- `input[name=searchInput]` = conversation search
- `a[href="/direct/new/"]`, `a[href="/direct/requests/"]`
- conversation rows are **not** anchors and have **no** `href`

**Thread** (`/direct/t/<id>/`):

- the inbox DOM stays mounted underneath the thread (both are present in the DOM)
- the message composer is **not** an `<input>`; only `searchInput` was found.
  It is likely `[contenteditable]` or a `<textarea>` — confirm in M3
- message actions: `div[role=group][aria-label="Message actions"]`
- sender avatars link to `/<username>/`, so profile navigation **is** reachable
  from a thread

Because conversation rows are not anchors, `a[href]` click interception is not
enough on its own. `pushState` is the real navigation path. This validates the
three-layer design and makes the history interception the primary defense.

### 2.5 The reel viewer (the hard one)

Measured while a reel from a DM was playing fullscreen:

| Signal | Observed |
| --- | --- |
| `location.href` | `.../direct/t/115950719795361/` — **unchanged** |
| `onUpdateVisitedHistory` | no event |
| `[role=dialog]` | **0** |
| `<video>` elements | **3** (prev, current, next) |
| Video geometry | 411×792 each, one `paused: false` |
| Video source | `blob:` URL |
| Scroll container | 792 tall, `scrollHeight` 2439 ≈ 3 slides |
| Anchors in viewer | `/<user>/reels/`, `/reels/audio/<id>/` |
| Active reel permalink | **not present in the DOM** |

Conclusions:

1. **The reel viewer cannot be detected or blocked by URL.** It emits no
   navigation event whatsoever.
2. **There is no shortcode to pin.** The active reel has no permalink in the DOM,
   so "pin the shortcode and bounce on change" (the original plan) is not
   possible from inside the viewer. The shortcode can only be known from the DM
   message that was tapped, and even then it is not observable while viewing.
3. **The carousel is finite and structural.** Three slides live in one scroller.
   Removing the other two leaves nothing to scroll to. This is the mechanism to
   build focus mode on.

### 2.6 `disableVerticalScroll` is not a scroll lock

The original design assumed the plugin's `disableVerticalScroll` setting gave a
native-level scroll lock. It does not. In the Android implementation:

```
InAppWebView.java:351
  setVerticalScrollBarEnabled(!customSettings.disableVerticalScroll && ...)
```

It hides the **scrollbar**. Scrolling is unaffected. Any plan that relies on it
is wrong. The correction is recorded in `SPEC.md` §5.1.

---

## 3. Design corrections forced by the spike

### 3.1 Sanitizer scope shrinks

M3 no longer needs to hide a global nav on DM pages, because none is rendered.
Remaining cosmetic work:

- hide the notes entry ("What's new… Your note") if desired — **decision: left
  visible per product choice** (notes are not stories)
- hide profile links/avatars only if they prove to be a usability problem; they
  are already blocked by `UrlPolicy`
- hide the "Open in app" / install banner if it appears on DM pages (not observed
  in this spike, but it appears on the feed)
- hide the cookie consent dialog **only after the user has answered it once**;
  never auto-accept consent

### 3.2 History interception is primary, not secondary

Conversation opens are `pushState`, not anchor clicks and not page loads. The
document-start history wrapper is therefore the main enforcement point, not a
belt-and-braces extra. It must:

- wrap `pushState` **and** `replaceState`
- resolve relative URLs against `location.href`
- refuse disallowed destinations **before** they take effect
- never throw, even if the page replaces `history.pushState` later (re-wrap on
  `pageshow` and on a low-frequency interval)

### 3.3 Reel focus mode, revised

The pin-the-shortcode plan is dead. New approach, all selector-free:

1. **Detect** the viewer: a `<video>` that covers at least 60% of the viewport
   width and 50% of its height and intersects the viewport. Polled every 600 ms
   and on `DOMContentLoaded`.
2. **Find the scroller**: walk up from that video to the nearest ancestor with
   `scrollHeight > clientHeight + 100` and `overflowY` in `auto|scroll`. A
   single-video viewer has no such ancestor; that is a normal shape, not an
   error.
3. **Collapse the carousel** (only when a scroller exists): hide each child of
   the slide container unless it contains the active video. `scrollHeight`
   becomes equal to `clientHeight`.
4. **Freeze gestures**: a document-level capture `touchmove` handler calls
   `preventDefault`, and the container gets `touch-action: none`,
   `overscroll-behavior: contain`, and (for a carousel) `overflow: hidden`.
   Blocking only the carousel was not enough: Instagram's own dismiss gesture
   lives outside it, so a swipe closed the viewer. Taps are left alone.
5. **Re-check** on every tick, because React may re-add slides.
6. **Exit** by removing the injected styles and reloading the thread, which is
   cheaper and more reliable than trying to un-collapse React state.

No shortcodes are involved. A `ReelLink` / shortcode parser was planned but has
been **dropped**: the active reel has no permalink and DM attachments are not
anchors, so there is nothing to parse and nothing to pre-screen. Do not
reintroduce it without new evidence.

This was implemented in M5; delivery notes in §11.

### 3.4 Focus-mode escape detection is now "did the viewer close"

Since there is no URL or shortcode to watch, the guard reports state changes:
`open`, `closed`, `blocked` (Mode B), `freeze-failed`. If the overlay is still
visible 2 s after detection and the freeze has not been applied, Dart leaves the
viewer and shows "Reels aren't available in this mode". The delay exists because
a transient failure while Instagram is still mounting the overlay is normal.

---

## 4. Confirmed selector inventory

Only semantic attributes. Never generated classes.

| Purpose | Selector | Page |
| --- | --- | --- |
| DM top bar | `div[role=navigation]` | inbox, thread |
| DM back | `svg[aria-label="Back"]` | inbox, thread |
| New message | `a[href="/direct/new/"]` | inbox, thread |
| Message requests | `a[href="/direct/requests/"]` | inbox, thread |
| DM search | `input[name=searchInput]` | inbox, thread |
| Profile link | `a[aria-label^="Open the profile page of"]` | thread |
| Message actions | `div[role=group][aria-label="Message actions"]` | thread |
| Global bottom nav | `nav [role=tablist]` | feed only |
| Nav entries | `a[href="/"]`, `[href*="/explore/"]`, `[href*="/reels/"]`, `[href*="/direct/"]` | feed only |
| Login fields | `input[name=username]`, `input[name=password]` | login |

---

## 5. What works right now

- A real Instagram session loads, survives an app restart, and is usable inside
  the WebView. Cold start lands directly on the DM inbox.
- **Three enforcement layers are live** (see §9): native `shouldOverrideUrlLoading`,
  `onUpdateVisitedHistory` backstop, and a document-start JS guard whose rules are
  generated from `UrlPolicy` (verified: the debug screen reports `IN SYNC`).
- **`UrlPolicy` is complete and tested**: 65 unit tests cover every route in
  `SPEC.md` §4.3, the redirects, the reel/post modes, non-http schemes, host
  spoofing, ports and path traversal. Deny-by-default is enforced.
- **The sanitizer is live.** A v1 stylesheet is injected at document start and
  hides Instagram's new-message pencil (`/direct/new/` is blocked). The debug
  screen prints the sanitizer report: version, injection state, and the live
  match count for every selector parsed out of the CSS. Verified on the inbox and
  on a thread. `test/sanitizer_css_test.dart` enforces the "no generated classes"
  rule at build time.
- `InstagramRoutes` is the only place that builds Instagram URLs, and a test
  asserts the app can navigate to every URL it builds.
- The app shell exists: app bar with back/reload/debug, progress bar, error and
  offline views, blocked notice, and back handling that exits only from the
  inbox.
- The debug screen shows the current URL, runs Compare / Click test / Native
  load / Sanitizer / Reel probe, and displays the guard log.
- **Single-reel focus mode works** (Mode A, `SPEC.md` §5.1): tapping a reel in a
  thread opens it with a "Single reel · Close" banner; swiping neither advances
  nor dismisses; Close and Android back return to the thread. **Mode B**
  (`--dart-define=MI_BLOCK_REELS=true`) closes the viewer immediately with a
  notice and restores the thread. Both verified on device.
- **Settings sheet exists** with Clear session (confirmation dialog required) and
  the unofficial-viewer disclaimer. Expired sessions are detected and explained.
- On device, verified in M2: `/explore/` blocked (click and native load),
  `/reels/`, profiles, `/accounts/edit/`, `https://example.com/` blocked,
  `instagram://` cancelled silently, `/` redirected to the inbox, thread open
  and back, reload preserves the page, back from inbox exits the app.
- `flutter analyze` is clean and `flutter test` is green (74 tests).

## 6. What does not work / does not exist yet

- **The reels preference is not persisted.** There is no UI toggle; the mode is
  a compile-time flag (`MI_BLOCK_REELS`). That is M6.
- **Clear session has not actually been executed** on device. The confirmation
  flow is verified; the destructive path is deliberately deferred until the
  logged-in reel work was finished. It must be walked before release.
- **Post viewing from a DM is untested.** `UrlPolicy` allows `/p/<code>/`, but M5
  only exercised reels.
- No release build has been attempted; the debug screen is still compiled into
  release code paths behind `kDebugMode`.
- The M0 probe data is from one session on one account; treat it as a snapshot,
  not a contract.
- `assets/test_site/` does not exist yet (M7). Widget tests cover the settings
  sheet only; the browser screen has no widget test.

## 7. Known unknowns

- Whether the reel carousel collapse survives Instagram's re-renders for more
  than a few seconds. Needs live testing in M5.
- Whether voice/video call buttons work in a WebView (mic/camera permissions).
  Left visible by product decision; unverified.
- Whether the message composer behaves with the soft keyboard on small screens.
- Whether `?deoia=1` is a stable or A/B-tested landing parameter.
- Whether Instagram shows "open in app" interstitials on DM pages after a while.

---

## 8. M1 delivery notes

What M1 added:

| File | Purpose |
| --- | --- |
| `lib/navigation/url_policy.dart` | `UrlPolicy.decide(Uri)` → `UrlDecision` |
| `lib/navigation/instagram_routes.dart` | canonical URLs; the only place they are built |
| `lib/app.dart` | `MaterialApp`, light/dark theme, single route |
| `lib/main.dart` | bootstrap; enables WebView debugging in debug builds only |
| `lib/webview/browser_screen.dart` | placeholder shell; M2 fills in the WebView |
| `test/url_policy_test.dart` | 61 tests, positive + near-miss for every rule |

### `UrlPolicy` in one paragraph

`decide(Uri)` returns one of four verdicts: `allow`, `redirect` (with a target),
`block`, or `external`. Non-http(s) schemes are `external`. Any host that is not
exactly `instagram.com`, `www.instagram.com` or `m.instagram.com` is `block`.
Non-standard ports are `block`. Paths are matched case-sensitively and by path
only — query strings and fragments are ignored, which is why `/?deoia=1`
correctly redirects to the inbox. Everything not explicitly allowed is `block`.
Reel permalinks are blocked unless `UrlPolicy(reelPolicy: ReelPolicy.allow)` is
constructed; that switch flips in M5.

### Verify M1

```bash
flutter analyze     # must be clean
flutter test        # 65 tests, all green
```

---

## 9. M2 delivery notes

What M2 added:

| File | Purpose |
| --- | --- |
| `lib/core/config/app_config.dart` | user agent, start URL, `reelPolicy`, log capacity |
| `lib/core/logging/guard_log.dart` | bounded in-memory log of decisions, with dedupe |
| `lib/webview/webview_settings.dart` | the single `InAppWebViewSettings` factory |
| `lib/webview/browser_screen.dart` | WebView host + all enforcement wiring + back handling |
| `lib/ui/common/error_view.dart` | network / server failure states |
| `lib/ui/debug/debug_screen.dart` | Compare, Click test, Native load, guard log |
| `assets/js/guard_document_start.js` | history wrapper, click capture, popup denial |
| `assets/css/hide_instagram_chrome.css` | placeholder; sanitizer lands in M3 |

### The three layers

1. **`shouldOverrideUrlLoading`** — every main-frame page load. Applies
   `UrlPolicy`. `redirect` cancels and loads the target in a microtask (calling
   `loadUrl` inside the callback is re-entrant). `block` cancels and shows the
   notice. `external` cancels silently.
2. **`onUpdateVisitedHistory`** — backstop for client-side route changes. If the
   new URL is blocking or a redirect, the app loads the inbox.
3. **`guard_document_start.js`** — runs `AT_DOCUMENT_START`, before Instagram's
   scripts. Wraps `pushState`/`replaceState`, intercepts anchor clicks in the
   capture phase, denies `window.open`. Its rules come from
   `UrlPolicy.toGuardRulesJson()`, injected as `window.__MI_RULES` ahead of the
   script body. Never hand-edit rules in the JS.

Layers 1 and 2 are main-frame only. Subframe navigation is allowed: an iframe
that navigates the top frame re-enters layer 1 as a main-frame navigation, so
allowing subframes adds no escape route. This is stated in `SPEC.md` §4.4.

### Findings worth keeping

- **On Android, `shouldOverrideUrlLoading` is NOT called for a programmatic
  `loadUrl`** from the app itself. The debug screen's "Native load" test proved
  this: the blocked page loaded, and `onUpdateVisitedHistory` caught it and
  recovered to the inbox. That is why `_loadUrl` validates internally and why
  the layer-2 backstop is not optional.
- The in-page guard's bridge (`window.flutter_inappwebview`) attaches slightly
  after document-start, so reports are queued and flushed on
  `flutterInAppWebViewPlatformReady` plus a 500 ms interval.
- Instagram fires the same navigation callback up to 3× per transition; the log
  uses `addDeduplicated` to stay readable.
- `onLoadStop` logs every allowed main-frame load. This is how you confirm the
  guard is actually seeing traffic (the log is empty otherwise).

### Manual verification performed (SPEC §10.1)

Done on `emulator-5554` with a real logged-in session, driven with `adb` taps:

- cold start → inbox; session persisted across a rebuild and restart
- thread opens; back returns to inbox
- back from inbox exits to the launcher
- reload preserves the page
- Compare reports `IN SYNC` for every preset
- `/explore/` refused by click and by native load; page unchanged
- `/reels/`, `/<user>/`, `/accounts/edit/`, `/stories/...`, `/direct/new/`,
  `https://example.com/` all refused
- `instagram://user?...` cancelled with no external app launch
- `/` redirected to the inbox

---

## 10. M3 delivery notes

M3 turned out to be small, because M0 proved DM pages carry no global navigation.
The work was therefore infrastructure plus one honest rule, not a long selector
list.

| File | Purpose |
| --- | --- |
| `assets/css/hide_instagram_chrome.css` | the only place selectors may live; v1 |
| `assets/js/guard_load.js` | injects the CSS, re-ensures it, exposes the report |
| `lib/webview/browser_screen.dart` | loads JS + CSS, builds one document-start bundle |
| `lib/ui/debug/debug_screen.dart` | "Sanitizer" button renders the report |
| `test/sanitizer_css_test.dart` | build-time guardrails for the stylesheet |

### What v1 hides, and why only that

One rule: `a[href$="/direct/new/"] { display: none !important; }`.

`/direct/new/` opens a global recipient search and is deliberately blocked
(`SPEC.md` §4.5). A visible pencil that always refuses is a dead end, so the
entry point is hidden. Nothing else is hidden:

- notes tray: left visible by product decision;
- profile avatars and links: left visible; `UrlPolicy` refuses their targets;
- `div[role=navigation]`: never touched — it is Instagram's own DM top bar.

Do not add selectors speculatively. Each one needs a reproduced leak first
(AGENTS.md §4).

### How the sanitizer is wired

`browser_screen.dart` loads three assets and concatenates them into a single
document-start user script, in this order:

1. `window.__MI_RULES` (generated from `UrlPolicy`)
2. `window.__MI_SANITIZER = {version, css}` (CSS text plus the version parsed out
   of the stylesheet's header comment)
3. `guard_document_start.js` (navigation veto)
4. `guard_load.js` (stylesheet injection, removals, report)

One script, not four user scripts, because the order must be guaranteed and the
plugin gives no ordering contract across separate scripts. The CSS is injected at
document start, so there is no flash of unfiltered chrome.

`guard_load.js` re-inserts the stylesheet if it disappears, keeps a
MutationObserver for the (currently empty) removal list, and defines
`window.__miSanitizerReport()`. The report parses the CSS text at call time, so it
cannot drift from the stylesheet: there is no second selector list to maintain.

### The report

Debug → Sanitizer prints JSON: `version`, `url`, `styleInjected`, and one
`{selector, count}` pair per rule, plus `removals`. A count of `0` is normal on a
page that lacks the element; `-1` means an invalid selector, which is a bug in
the CSS. On both the inbox and a thread the v1 rule reports `count: 1`.

### Verify M3

```bash
flutter analyze                 # clean
flutter test                    # 71 tests
```

On device: open the inbox, confirm no pencil in the DM top bar and no gap; open a
thread, confirm the same; Debug → Sanitizer reports `styleInjected: true` and the
rule with a count. Manual checklist §10.2 walked on 2026-11-18.

### Next

M4 (session/clear-session) and M5 (reel guard) are both delivered; see §11.

---

## 11. M4 and M5 delivery notes

### M4 — session

| File | Purpose |
| --- | --- |
| `lib/ui/settings/settings_sheet.dart` | the sheet: Clear session + disclaimer |
| `lib/webview/browser_screen.dart` | `_clearSession`, expiry detection, notice |
| `test/settings_sheet_test.dart` | 3 widget tests for the confirmation flow |

`_clearSession()` deletes cookies (`CookieManager.deleteAllCookies`), web storage
(`WebStorageManager.deleteAllData`), all cache including disk
(`InAppWebViewController.clearAllCache` — a **static** in 6.2.0-beta.3), and the
back-forward list (`clearHistory`), then loads the login page. A failure in any
step is logged and the login page is still loaded: never leave the user on a
signed-in page because cleanup half-failed.

Expiry detection: `_sawAuthenticatedPage` becomes true on any non-login load. A
load of `/accounts/login` while that flag is set and `_clearingSession` is false
shows "Your session ended. Sign in again." Both flags are set by `_clearSession`
so a deliberate sign-out is not reported as an expiry.

**Not yet walked:** the actual sign-out. The confirmation dialog and its Cancel
path were verified on device; the destructive path was skipped because signing
out would have blocked the logged-in reel work below. Walk §10.3 before a
release, including "history does not keep the old page".

### M5 — single-reel focus mode

| File | Purpose |
| --- | --- |
| `assets/js/guard_load.js` | detection, collapse, freeze, reports, diagnostics |
| `lib/webview/browser_screen.dart` | `miReelState` handler, banner, back, close |
| `lib/ui/debug/debug_screen.dart` | "Reel" button calls `window.__miReelState()` |
| `lib/core/config/app_config.dart` | `MI_BLOCK_REELS` compile-time switch |

How it works, in one paragraph: every 600 ms the guard looks for a `<video>`
covering at least 60% of the viewport width and 50% of its height. If it finds
one, it either collapses the carousel around it (when a scrollable ancestor
exists) or treats it as a single-video viewer. Either way it installs a
document-level capture `touchmove` blocker, sets `touch-action: none` and
`overscroll-behavior: contain` on the video's container, and reports `open`. Dart
shows the banner; Android back and the banner's Close both call `_closeReel()`,
which reloads the page and returns to the thread.

### Findings worth keeping

- **The viewer has two shapes.** The M0 spike saw three slides in one scroller
  (`scrollHeight 2439`). On 2026-11-18 the same DM mounted **one** 411x734 video
  with no scrollable ancestor at all. The guard must not treat "no scroller" as a
  failure — in that shape there is nothing to collapse, and the freeze is the
  whole defense. `applyReelFreeze()` returns `'ok'` (carousel) or `'single'`.
- **A document-level `touchmove` blocker is required.** Blocking only the
  carousel let a swipe close the viewer (Instagram's dismiss gesture listens
  outside the carousel). Taps are intentionally left working.
- **`applyReelFreeze()` returns a reason string** (`no-video`, `no-scroller`,
  `no-container`, `ok`, `single`). The first version returned a boolean and
  silently reported `freeze-failed`; the strings are what found the single-video
  shape.
- **Bug found and fixed: `RULES` was not in scope.** `guard_load.js` read a bare
  `RULES`, but that identifier only exists inside the *other* script's IIFE. The
  read threw on every tick and was swallowed by the reel guard's `try/catch`, so
  the guard looked completely absent. It now reads `window.__MI_RULES`. Lesson:
  the guard's "never break the page" catch can hide real bugs; use the `[mi-reel]`
  console line and the debug probe, not silence.
- **Freeze failure has a 2 s grace period.** The overlay mounts in stages; a
  failed pass during mount is normal. Only a continuous failure for 2 s reports
  `freeze-failed`, at which point Dart shows "Reels aren't available in this
  mode" and reloads.
- **Closing is a reload.** The viewer exposes no close control we can depend on,
  so the thread is reloaded. It returns to the same thread but not to the same
  scroll position; do not promise otherwise.
- `onLoadStop` clears `_reelOpen`, so a navigation can never leave the app stuck
  in focus mode.
- The debug screen's "Reel" button prints `window.__miReelState()` plus every
  `<video>` rect and the chain of ancestors with their overflow. That is how the
  single-video shape was diagnosed, and it is the first thing to check if focus
  mode regresses.

### Verification performed (SPEC §10.4)

Mode A, `emulator-5554`, 2026-11-18:

- reel opened from the thread; banner "Single reel · Close" appeared
- debug probe: `detail: "ok"`, `hiddenSlides: 1`, `frozen: true` on the carousel
  shape; `detail: "single"` on the single-video shape
- two swipes up: still the same reel
- swipe down: viewer stayed open
- Close: returned to the thread
- Android back while open: left the reel, not the thread

Mode B (`flutter run --dart-define=MI_BLOCK_REELS=true`):

- reel tapped, snackbar "Reels aren't available in this mode", viewer closed,
  thread restored

### Still to do for M5

1. Open a **post** from a DM and confirm it does not open a feed.
2. Confirm no hardware-keyboard/media "next" affordance reaches a second reel.
3. Background/foreground the app while a reel is open and confirm focus mode
   recovers (or exits cleanly).
4. Re-run with the normal build (no `--dart-define`) after Mode B testing, so the
   installed app is back on the default mode.

### Next

M6: persisted reels preference (replaces `MI_BLOCK_REELS`), About/version,
release manifest permissions, release build smoke test. The reels toggle belongs
in `SettingsSheet`; persistence should use `shared_preferences` only if that
dependency is justified in writing here first (AGENTS.md §2.6).
