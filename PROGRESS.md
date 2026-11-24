# PROGRESS.md

State of the project for whoever picks this up next. Read this first, then
`SPEC.md` for intended behavior and `AGENTS.md` for rules.

**Last updated:** 2026-11-24
**Current milestone:** M8 complete. Every milestone in `SPEC.md` §9 is delivered:
M0–M8, with B1 (sign-in from a signed-out state, §15) fixed and verified on
device.
**Next action:** walk `SPEC.md` §10.6 on the emulator and tune the motion to
taste. The animation is a first pass (see §17); durations, distance and curve are
expected to change after seeing it on a real screen. Before a release, also walk
the rest of §10 on real Instagram — the fixture tests (§16) prove the wiring, not
Instagram's current DOM. The two open checklist items remain post-from-DM
(untested: the test thread has no post) and a simulated session expiry.

> **Bugs are expected.** A green test suite and a walked checklist only cover the
> paths someone actually exercised. A change that passes its own milestone can
> still break a flow that nobody re-ran. Every open bug gets an entry in §15; a
> fix is not done until the entry records the cause and the verification.

---

## Status board

| Milestone | Status | Notes |
| --- | --- | --- |
| M0 Feasibility spike | **Done** | Findings below. Spike code deleted in M1 |
| M1 Skeleton + pure core | **Done** | `UrlPolicy`, `InstagramRoutes`, app shell, 65 tests |
| M2 Enforcement | **Done** | Three layers live; verified on device, see §9 |
| M3 Sanitizer | **Done** | Small v1: hides the new-message pencil; report in debug. See §10 |
| M4 Login + session | **Done** | Settings, clear-session control, expiry notice, 3 widget tests. Destructive path walked 2026-11-23 (§9) |
| M5 Single-item focus | **Done** | Reel guard and Mode B verified on device; post-from-DM path untested (no post in the test thread). See §11 |
| M6 Settings/debug | **Done** | Persisted reels toggle, version, release manifest, release smoke test. See §14 |
| M7 Regression tests | **Done** | Fixture site + 8 on-device integration tests. See §16 |
| M8 Motion | **Done (first pass)** | Cosmetic inbox↔thread slide, setting + reduce-motion. See §17 |

**Open bugs:** none. B1 (§15) was fixed and verified on device on 2026-11-23.

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
- **`UrlPolicy` is complete and tested**: unit tests cover every route in
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
  nor dismisses; Close and Android back return to the thread. **Mode B** is now
  the "Block reels" choice in Settings; it closes the viewer immediately with a
  notice and restores the thread. Both verified on device.
- **Settings sheet exists** with the persisted reels choice, Clear session
  (confirmation dialog required), the version, and the unofficial-viewer
  disclaimer. Expired sessions are detected and explained.
- On device, verified in M2: `/explore/` blocked (click and native load),
  `/reels/`, profiles, `/accounts/edit/`, `https://example.com/` blocked,
  `instagram://` cancelled silently, `/` redirected to the inbox, thread open
  and back, reload preserves the page, back from inbox exits the app.
- **The guards are covered by on-device fixture tests** (M7, §16): 8 integration
  tests run the real `BrowserScreen` wiring against `assets/test_site/`, covering
  an allowed page, blocked click, vetoed history change, native-load recovery,
  the sign-up click veto, the sign-up reload backstop, and both reel modes.
- `flutter analyze` is clean, `flutter test` is green (100 tests) and
  `flutter test integration_test -d emulator-5554` is green (8 tests).

## 6. What does not work / does not exist yet

- **Post viewing from a DM is untested.** `UrlPolicy` allows `/p/<code>/` and a
  standalone post page was verified, but the DM-attachment path was not: the test
  thread contains only a reel.
- **Session expiry has not been observed** on device. The detection code exists;
  the checklist item stays open until a real expiry happens.
- **The client-side sign-up flow is a best-effort block**, not a guarantee
  (§4.7). Its labels and DOM markers can change.
- **The fixture site is a model, not Instagram.** It proves the wiring behaves
  as designed; it cannot prove that Instagram's current DOM or URLs still match
  the selectors and rules. Real-server behavior stays manual (§10 checklists).
- The M0 probe data is from one session on one account; treat it as a snapshot,
  not a contract.

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

> The `--dart-define=MI_BLOCK_REELS` switch described below was removed in M6.
> Mode B is now Settings → Block reels, persisted with `shared_preferences`
> (§14). The rest of this section is the historical M4/M5 record.

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

**Destructive path walked 2026-11-23.** Confirmation dialog → Clear deleted the
cookies (Instagram asked for cookie consent again) and landed on the login page.
Declining optional cookies showed the login form. Back from login did not reveal
the old thread (history was cleared); it reloaded login. Force-stop and relaunch
stayed on login. The expiry-notice path was not triggered by a real expiry and
remains unverified on device.

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

### M5 follow-up results (2026-11-23)

1. **Post from a DM — still open.** The test thread contains only a reel, so the
   DM-attachment path could not be walked. A standalone `/p/<code>/` page was
   verified instead: it renders as one "Post" view with no feed and no scrolling
   beyond it. That is what exposed the chrome leak fixed in §13.
2. **Keyboard/media "next" — done.** With a reel open, `KEYCODE_MEDIA_NEXT`,
   `KEYCODE_DPAD_DOWN` and `KEYCODE_PAGE_DOWN` changed nothing; the viewer stayed
   open and the same reel kept playing.
3. **Background/foreground — done.** Home then relaunch left the viewer open with
   the banner; two swipes up and one down still did nothing.
4. **Normal build restored.** The app now runs without `--dart-define`; Mode A is
   the installed behavior again.

### Next

M6 was the next step at the time and is now delivered; see §14. The remaining
known gaps are listed in §6.

---

## 13. Post-page chrome and sanitizer v2 (2026-11-23)

While checking the M5 post item, a standalone post page
(`https://www.instagram.com/p/C9k8L3GvOMD/`) turned out to render two pieces of
global chrome that DM pages never show:

1. a fixed bottom tab bar (Home / Explore / Reels / Messages), and
2. a fixed "Use the app" install banner.

Both are cosmetic leaks, not security holes: `UrlPolicy` still refuses every
destination behind those links. But SPEC §8 says global navigation must be
hidden, so v2 fixes them.

Neither node has a semantic attribute (`role`, `aria-label`, `href` on the
wrapper). A CSS `:has()` selector would match every ancestor up to `<body>` and
hide the whole page, so the hide is structural in `guard_load.js`:

- find `a[href="/explore/"]` / `a[href="/reels/"]`, walk up to the fixed
  ancestor with height ≤ 180 px, hide that ancestor;
- find a `button` whose entire label is `Use the app`, hide its fixed ancestor.

It runs at document start, on `DOMContentLoaded`, on `pageshow`, on the
mutation-observer flush, and on a 1.5 s timer. DM pages are untouched because
they contain neither marker. The sanitizer report gained `chromeHidden`, a count
of nodes hidden this way.

Verified on the post page: tab bar and banner gone, post fills the screen.
Inbox and thread: unchanged. Sanitizer version is now **2**; the stylesheet itself
is unchanged (still one rule). Tests: 78, all green.

One CSS housekeeping note: the stylesheet header used to say global nav is never
rendered. That is only true of DM pages; the comment now says so.

---

## 12. Post-M5 cold-boot fix — `/consent/` (2026-11-23)

A cold start on 2026-11-23 exposed a real gap. Instagram redirected the inbox to
`https://www.instagram.com/consent/?flow=user_cookie_choice_v2&source=pft_user_cookie_choice`,
`UrlPolicy` blocked it (deny by default), and the WebView was left on a **blank
page** with the "Not available" notice. The session was fine; the only problem
was that the consent interstitial had no allow rule.

Fix: `/consent` is now an allowed exact path. It is Instagram's own cookie
consent page, shown once; the app never accepts it on the user's behalf
(`SPEC.md` §8). Two tests were added: the real consent URL with its query is
allowed, and `/consent-notice/` and `/consent/extra/` stay blocked. Total unit
tests: 78.

After the fix, a cold start showed the consent page, and choosing "Decline
optional cookies" landed on the inbox with the session intact and the pencil
still hidden. `SPEC.md` §4.3 has the new row.

Lesson for whoever is next: a cold boot exercises redirects that a warm session
never shows. Run the cold-start checklist after any policy change, not only
after a feature change.

---

## 14. M6 delivery notes — settings, About, release (2026-11-23)

### What changed

| File | Purpose |
| --- | --- |
| `lib/core/settings/app_settings.dart` | persisted reels choice; the only stored state |
| `lib/main.dart` | loads settings before `runApp` |
| `lib/app.dart` | passes settings to the browser screen |
| `lib/webview/browser_screen.dart` | rebuilds the policy on change, replaces the injected script, reloads |
| `lib/ui/settings/settings_sheet.dart` | reels segmented control, version, clear session |
| `lib/core/config/app_config.dart` | `version` constant; `MI_BLOCK_REELS` removed |
| `test/app_settings_test.dart` | persistence and notification tests |
| `test/app_config_test.dart` | version stays in sync with `pubspec.yaml` |
| `test/settings_sheet_test.dart` | toggle + confirmation-flow tests |
| `android/app/src/main/AndroidManifest.xml` | `INTERNET`, label, `allowBackup=false` |

### Dependency justification (AGENTS.md §2.6)

`shared_preferences: ^2.5.6` was added for one boolean. Why it earns its place:

- Android's app-data directory is not reachable from Dart without another
  plugin, and a hand-written platform channel is more native code to own and
  review than this official Flutter plugin.
- Only `reels_blocked` is stored. No user identifier, no session, no message
  content. `allowBackup=false` keeps even that out of cloud backups.
- It brings ~18 transitive packages, almost all per-platform implementations
  that do not run on Android. That is the cost; it is recorded here deliberately.

### How the reels setting works

`AppSettings` is loaded before `runApp`, so the document-start bundle is correct
on the very first page. The sheet writes through `setBlockReels`, which updates a
`ValueNotifier<ReelPolicy>` and then the store. The browser screen listens,
rebuilds `UrlPolicy`, rebuilds the bundle, **replaces the WebView's user script**
and reloads.

That last step was a bug worth remembering: `initialUserScripts` is only read
when the platform WebView is created. Rebuilding the widget does not change the
script on an existing WebView, so the first version of this feature only applied
after a cold start. `removeAllUserScripts()` + `addUserScript()` + `reload()`
fixed it. Verified live: block → allow → block without restarting the app, with
`window.__MI_RULES.reelPolicy` checked over CDP each time.

### Release manifest

The main manifest had **no `INTERNET` permission**; only the debug and profile
manifests did. Every release build would have shown a blank page. Fixed, along
with:

- `android:label="Minimal Instagram"`;
- `android:allowBackup="false"` — a WebView session should not be copied into a
  cloud backup.

`aapt2 dump badging` on the release APK: `versionName='1.0.0'`,
`application-label:'Minimal Instagram'`, `uses-permission: INTERNET`.

### Release smoke test (SPEC §10.5), 2026-11-23

`flutter build apk --release` → 48.7 MB. Uninstalled the debug app, installed the
release APK on the emulator, then:

- cold start reached Instagram (consent page) → `INTERNET` works;
- no debug icon; settings and reload remain;
- declining consent showed the login page;
- **"Create new account" was refused** — stayed on login with the "Not available"
  notice (after the fix below; the first run exposed the bypass);
- Settings showed `Minimal Instagram 1.0.0`;
- switching to Block reels survived force-stop + relaunch;
- Clear session deleted the cookies (consent reappeared), and after declining the
  login page returned; the reels choice survived (it is app storage, not web
  storage).

### The client-side sign-up bypass (found by the release test)

The first release smoke test failed in an interesting way: tapping "Create new
account" showed the sign-up screen even though the policy blocks
`/accounts/emailsignup/`. Investigation (debug build + CDP):

- the control is a `div[role="button"]` whose tap target is a `<span>` **seven**
  levels below the labelled div;
- the sign-up flow is rendered client-side; the URL stays on
  `/accounts/login/...` and `history.length` stays 1, so `UrlPolicy` and both
  native layers see nothing;
- the first guard walked only six ancestors, so it never found the label;
- a synthetic `.click()` was blocked, but a real tap opened the flow on a
  press event handled at window level.

Fix, in two layers:

1. `guard_document_start.js` walks up to 12 ancestors, matches a short
   `aria-label` deny list (`create new account`, `create account`, `sign up`,
   `sign up with email`) and refuses click, Enter, and press events on `window`
   capture. It reports the intended route, so the guard log shows a `[surface]`
   block and the user gets the normal notice.
2. `guard_load.js` keeps a backstop: if the sign-up markers
   (`input[type="tel"][aria-label="Mobile Number"]` or
   `button[aria-label="Sign up with email"]`) appear on a login page, it reports
   the block and reloads. Checked every 500 ms and on DOM mutations.

Verified after the fix: tapping the control keeps the login page and shows the
notice; the guard log reads
`[surface] block https://www.instagram.com/accounts/emailsignup/ — stopped inside the page`.
This is **best effort**, not a guarantee: it depends on an Instagram label and a
DOM marker. It is documented in `SPEC.md` §4.7 and `AGENTS.md` §2.7 alongside the
reel guard. If the label changes, the backstop still kicks the user back to login;
if the markers change too, the surface would be reachable, and that must be
recorded as breakage rather than denied.

### Verify M6

```bash
flutter analyze                  # clean
flutter test                     # 85 tests
flutter build apk --release
```

On device, walk `SPEC.md` §10.5. The app is currently left on the login page
(session cleared during the test); sign in with the test account to resume
manual DM/reel checks.

### Next

M7: `assets/test_site/` served by `InAppLocalhostServer`, integration tests that
exercise blocking without a login, and a home for the JS guard tests. The
client-side sign-up guard is a good first fixture: a fake login page with a
`role="button"` that renders a fake sign-up surface would pin the behavior.

---

## 15. Open bugs

Bugs are expected, not exceptional. A milestone checklist only covers the paths
that were walked; a later change can regress a flow nobody re-ran. Every open bug
gets an entry here, written so the next agent can resume without context. When it
is fixed, keep the entry, mark it **FIXED**, and record the cause, the fix and how
it was verified.

### B1 — Signing in from a signed-out state bounces back to login (2026-11-23, FIXED 2026-11-23)

**Symptom.** From a signed-out state, the user signs in with the test account.
The credentials are accepted, but when the app navigates towards the messages
section it shows the "Not available in Minimal Instagram" notice and the login
page stays on screen. A cold start is signed out again (no usable session).

**Why this slipped through.** Every device test in M5 and M6 started from an
already-signed-in session. M4's destructive test cleared the session and stopped
at the login page without signing back in. The automated tests do not touch real
Instagram at all. So `signed out -> sign in -> inbox` has not been walked since
M0, before the M6 sign-up guard and the `/consent` rule existed. This is the
first reported bug of that kind; assume other untested transitions can be broken
too.

**Expected behavior.** Sign in from the login page, land on
`/direct/inbox/`, and use the app normally. The session must survive a restart,
as described in `SPEC.md` §10.3.

**What is already ruled out (2026-11-23):**

- `/direct/inbox` and `/direct/inbox/` are allowed by `UrlPolicy`; both sides
  are covered by unit tests.
- `/accounts/login`, `/auth_platform`, `/auth_platform/codeentry`,
  `/accounts/onetap`, `/accounts/two_factor`, `/challenge...` and `/consent` are
  allowed.
- Loading `https://www.instagram.com/direct/inbox/` while signed out reaches
  Instagram and redirects to login, so the app does not block the inbox URL by
  itself.
- Tapping "Log in" with empty fields does not trip the sign-up control guard.
- The M6 sign-up guard's markers (`input[type="tel"][aria-label="Mobile Number"]`,
  `button[aria-label="Sign up with email"]`) are absent from the current login
  page, so the backstop should not be reloading it.

**Cause.** The logcat capture of the failed attempt showed the login chain, and
the last step was blocked:

```
[mi-guard] navigation allow https://www.instagram.com/auth_platform/?apc=…&deoia=1
[mi-guard] navigation block https://www.instagram.com/auth_platform/afad/?apc=…&deoia=1
```

`UrlPolicy` allowed `/auth_platform` and `/auth_platform/codeentry` as exact
paths, on the M0 observation that the 2FA step lived at `codeentry`. Instagram
renamed that sub-route; on 2026-11-23 the 2FA handoff is `/auth_platform/afad/`.
Deny-by-default cancelled the handoff, the app showed the blocked notice, and
Instagram fell back to `/accounts/login/?next=…/direct/inbox/…`, which is why the
login page reappeared and no session was established.

This was suspect 1 in the original list: a URL in the post-login redirect chain
that was not in the allowlist.

**Fix.** `/auth_platform/` is allowed as a **prefix**, the same way `/challenge/`
already is, because every sub-route under it is a step of signing in and
Instagram renames them. Changes:

- `lib/navigation/url_policy.dart`: `_authPlatformPrefix = '/auth_platform'`,
  matched with `path == prefix || path.startsWith('$prefix/')`; the two exact
  paths are removed from `_allowedPaths`. `toGuardRulesJson()` emits
  `authPlatformPrefix`.
- `assets/js/guard_document_start.js`: mirrors the prefix, read from that JSON,
  with the same fallback (`|| '/auth_platform'`).
- `test/url_policy_test.dart`: `/auth_platform/afad/?apc=…` is allowed;
  `auth_platform.evil/` and `auth_platformx/` are blocked (near-misses); the
  guard-JSON test now asserts the prefix.
- `SPEC.md` §4.3 route table and §10.3 checklist updated.

This is a narrow path prefix on the Instagram host, not a wildcard over
`instagram.com/*` or `/direct/*`.

**Verification (device, 2026-11-23).** Debug build reinstalled, session cleared,
signed in with the test account. Capture (`/tmp/opencode/b1fix_capture.log`,
since deleted with the temp dir):

```
18:06:38 navigation allow /auth_platform/?apc=…          -- auth platform handoff
18:06:41 navigation allow /auth_platform/afad/?apc=…
18:07:31 navigation allow /direct/inbox/?__coig_login=1&deoia=1
18:07:31 load       allow /direct/inbox/?__coig_login=1&deoia=1
```

No `navigation block` lines in the whole capture. The inbox rendered, a profile
link (`/toastu_/`) and a `history` redirect to `/` were blocked as designed, and
then the app was killed and cold-started again (new process, `18:09:38`) which
loaded `/direct/inbox/` directly — the session survived the restart, so the
"cold start is signed out again" half of the symptom is gone too.

`flutter analyze` clean; 89 tests pass.

**Status:** fixed and verified end to end on the emulator, including a cold
restart. Keep the entry as the record of the first state transition that was not
covered by a checklist item.

**Reproducing a blocked URL in future.** Run `flutter run -d emulator-5554`; the
debug build writes `[mi-guard]` lines to logcat (`adb logcat -s flutter chromium`)
and mirrors them to the Debug screen's guard log. A block line names the URL, the
verdict, the reason and the source (`navigation`, `history`, `load`, `click`,
`surface`, …). Always capture the exact URL before changing the policy.

**Do not** widen the policy to `/direct/*` or `instagram.com/*` to "make it
work". If a new route is genuinely required, add the narrow path, a unit test for
it and its near-miss, and document it in `SPEC.md` §4.3.

### B2 — Tapping a conversation bounced back to the inbox (2026-11-24, FIXED 2026-11-24)

**Symptom.** After the M8 motion work landed, tapping a conversation did not open
it: the app briefly showed the inbox again. The user described it as "the URL
filter is broken," but the filter was never the problem.

**Why it looked like a filter bug.** Deny-by-default *also* sends you back to the
inbox, so the symptom was indistinguishable from a blocked route at a glance.

**What was ruled out.** `git diff` showed `url_policy.dart`, `instagram_routes.dart`
and both guard scripts were byte-identical — the allow/block rules had not moved.
The guard log was the decisive evidence: tapping a conversation produced repeated
`[mi-guard] load allow .../direct/inbox/` lines and an occasional
`history redirect https://www.instagram.com/`, but **no** `/direct/t/<id>/` line at
all — not `allow`, not `block`. A genuine filter block always logs the offending
URL. The thread URL never becoming a navigation meant the WebView was being reset,
not policed.

**Cause.** The first motion implementation wrapped the WebView in a
`FractionalTranslation` so the platform view would slide. `flutter_inappwebview`
renders a native Android view, and inserting/removing a transform around it
forced the view to be re-created, which reloaded its initial URL (the inbox)
before the thread's `pushState` ever became a navigation.

**Fix.** Stop moving the platform view entirely. The motion is now drawn as a
Flutter-only curtain (`lib/ui/common/dm_transition_overlay.dart`) that sits *on
top of* the WebView as a sibling in the `Stack`, never as an ancestor. It is
pointer-transparent and always renders nothing when idle.

**Verification (device, 2026-11-24).** Rebuilt and reinstalled; drove the app via
`adb`. Confirmed over the WebView DevTools endpoint that tapping a conversation
lands on `https://www.instagram.com/direct/t/115950719795361/` and **stays** there
after the animation settles, with no `[mi-guard]` lines; the app-bar back returns
to `/direct/inbox/` cleanly. `flutter analyze` clean; 128 tests pass.

**Lesson.** The URL layer was correct the whole time. A "blocked" symptom can also
mean "the WebView got re-created" — and the guard log distinguishes the two,
because recreation produces no `block` line for the URL that was supposed to load.
Do not touch a native platform view with Flutter transforms.

---

## 16. M7 delivery notes — automated regression (2026-11-23)

M7 replaces "walk it by hand and hope" with an on-device test that drives the
real `BrowserScreen` against a local fixture site. It never touches Instagram and
needs no login, so it can run after every change.

### How to run

```bash
flutter analyze
flutter test                                       # 100 unit + widget tests
flutter test integration_test -d emulator-5554     # 8 on-device tests
```

The integration tests take about 15 s once the debug APK is cached. They build
and install the app, so keep the emulator running.

### What was added

- `assets/test_site/` — five static pages modelling the surfaces the guards care
  about: the inbox, a conversation with a shared reel, a blocked Explore page, a
  login page with a client-side sign-up control, and the sign-up surface itself.
  Each page carries a `data-test` marker so the test can tell which document is
  on screen.
- `integration_test/fixture_site_test.dart` — starts `InAppLocalhostServer` on
  port 8080 and pumps the real browser widget pointed at it.
- `UrlPolicy.fixtureSite(port:)` — same route rules, but the only reachable
  origin is `localhost` on the given port. It is a named constructor, not a
  parameter on the default one, so production code has no way to widen the host
  set. `withReelPolicy()` keeps the origin rules when the user flips the setting.
  `home` is the fixture inbox, so every recovery path (`_loadInbox`, `/` and
  `/direct` redirects) stays inside the fixture instead of jumping to Instagram.
- `toGuardRulesJson()` now emits `ports`, and `guard_document_start.js` reads it.
  The fixture server uses port 8080; without this the in-page guard would refuse
  its own page as an unexpected port.
- `BrowserScreen` gained `startUrl`, `policy` and `onControllerReady`. All three
  default to null, which selects today's production behaviour. They exist so the
  test can aim the same wiring at the fixture; `app.dart` does not pass them.
- `android/app/src/debug/AndroidManifest.xml` sets
  `android:usesCleartextTraffic="true"` so the WebView may open
  `http://localhost:8080`. Debug-only; the release manifest is untouched and the
  release policy still cannot reach localhost.
- `integration_test` added as a dev dependency. It ships with the Flutter SDK, so
  it does not enlarge the app's dependency surface (AGENTS.md §2.6).

### What the tests prove

| Test | Layer exercised |
| --- | --- |
| Inbox loads; new-message pencil hidden | policy allow + sanitizer CSS |
| Anchor to `/explore/` refused | in-page click guard |
| `history.pushState` to `/explore/` vetoed | in-page history guard |
| App-initiated load of `/explore/` recovered | `onLoadStop` last-resort guard |
| "Create new account" click refused | in-page forbidden-control guard |
| Sign-up markers trigger a reload | `guard_load.js` surface backstop |
| Single-reel mode freezes the viewer, Close leaves | reel guard, Mode A |
| Block-reels mode refuses the viewer | reel guard, Mode B |

Every test polls the live page through the WebView controller, because Flutter
cannot read or tap a platform view. The helper bounds each poll with a timeout:
a reload destroys the JavaScript context and `evaluateJavascript` can otherwise
never answer, which hangs the test rather than failing it. That failure mode cost
a full debugging round; keep the timeout.

### What it does not prove

- Nothing about Instagram's live DOM, URLs or account flows. Those stay manual
  (`SPEC.md` §10) because they need a real login.
- The fixture's reel carousel is shaped like the observed one (a scroll container
  of slides, only one intersecting the viewport) but is not Instagram's markup.
  A selector change on the real site is invisible here.
- The sign-up backstop test uses a fixture-only `?surface=1` switch that injects
  the real marker attribute once per session. It verifies the reload behaviour;
  it cannot verify that Instagram still uses that marker.

### Release note

`assets/test_site/` is bundled into release builds as well. It is a few KB of
static HTML, and it is unreachable: the production policy only allows Instagram's
hosts, and the in-page rules carry the same host list. If a future release
trimming pass wants it out, the fixtures can move behind a build flavour, but
that is not worth a second build configuration today.

---

## 17. M8 delivery notes — motion (2026-11-24)

### Why it was needed

On device (2026-11-24) the inbox → conversation change was confirmed to be an
instant hard cut: Instagram's mobile web renders **no** transition between the
two DM surfaces. It is a `history.pushState`, not a page load, so there is
nothing for the browser to animate and the swap looks abrupt.

### The constraint

Inbox and thread live in the **same** WebView, and Instagram keeps the inbox DOM
mounted underneath the thread (PROGRESS.md §2.4). There is no Flutter route push
or pop to hook, and there are not two screens to slide. The only honest options
were a cosmetic Flutter overlay or fighting Instagram's React DOM; the former was
chosen because it cannot break the page and keeps the URL layer as the sole
guarantee (AGENTS.md §2.7).

### What was added

| File | Purpose |
| --- | --- |
| `lib/navigation/dm_transition.dart` | pure `classifyDmTransition(from, to)` → `forward` / `back` / `none` |
| `lib/ui/common/dm_transition_overlay.dart` | Flutter-drawn sweep curtain (`AnimatedWidget`), never touches the WebView |
| `lib/core/settings/app_settings.dart` | persisted `animationsEnabled` (`animations_enabled`), default on |
| `lib/ui/settings/settings_sheet.dart` | Motion → "Slide transitions" switch |
| `lib/webview/browser_screen.dart` | trigger in visited-history and load-stop; `AnimationController`; reduce-motion guard |
| `test/dm_transition_test.dart` | forward / back / none sets + a drift test against `UrlPolicy` |
| `test/dm_transition_overlay_test.dart` | curtain geometry at 0/.5/1 and pointer transparency |
| `test/app_settings_test.dart` | animations default, persistence, notification |
| `test/settings_sheet_test.dart` | the Motion control and its notifier |

### How it works

1. `_onVisitedHistory` (the main signal for `pushState`) and `_onLoadStop`
   (the full-load fallback for the app-bar back) each keep the previous URL,
   compare it with the new one through `classifyDmTransition`, and call
   `_playTransition`.
2. `_playTransition` is gated by the setting, by
   `MediaQuery.disableAnimations`, and by a 300 ms debounce (a full load can
   surface through both callbacks).
3. The body `Stack` gains a topmost `DmTransitionOverlay` **sibling** (never an
   ancestor of the WebView). It sweeps an opaque, pointer-transparent curtain
   across the screen — forward right→left, back left→right — over 280 ms. On
   completion the direction resets to `none`, which renders nothing.
4. Reloads, cold starts, refused URLs, post pages and login pages all classify as
   `none`, so they never animate. `isReload` is also filtered on the history path.

### Honest limits and things to tune

- This is a **first pass**, left deliberately easy to iterate. The most likely
  changes after seeing it on the emulator are the duration (280 ms), the sweep
  easing (`Curves.easeInOut`) and whether a full wipe reads well versus a
  cover-and-fade.
- The WebView is **never moved**. Translating the native platform view was the
  first attempt and it broke navigation (see §15 B2), so the motion is drawn as a
  Flutter-only curtain over it. That is the safe, permanent shape, not a fallback.
- Because the content swaps instantly inside the WebView, the curtain **masks**
  the swap; it cannot show the old surface sliding out. That is the unavoidable
  consequence of one WebView, and it is not a native two-screen push.
- The motion is cosmetic. It decides nothing and blocks no input; a missing
  signal just means a hard cut, exactly as before.

### Verification

`flutter analyze` clean; `flutter test` green (128 tests). On device, confirmed
via CDP that tapping a conversation lands on `/direct/t/<id>/` and **stays** (no
bounce), and that the app-bar back returns to `/direct/inbox/` with no guard
decisions logged. The animation itself still needs a human eye against
`SPEC.md` §10.6.

### Verify M8

```bash
flutter analyze
flutter test
flutter run -d emulator-5554   # then walk SPEC §10.6
```
