# AGENTS.md

Operating rules for anyone (human or agent) changing this repository.
Read `SPEC.md` for **what** the app must do and `PROGRESS.md` for **where we are**.
This file is about **how** to change things without breaking the guarantees.

---

## 1. What this project is

A Flutter app that hosts `instagram.com` in a single WebView and exposes **only
Direct Messages**. Feed, Reels feed, Explore, Search, Profile, Settings and any
other Instagram surface are unreachable. Shared reels and posts open as a single
item, never a scrollable feed.

The app never sees, stores, or transmits credentials. Login happens inside the
WebView, in Instagram's own pages.

Supported platform: **Android** (primary and only tested target). iOS config
exists but is untested. Desktop/web targets are out of scope and must not be
used to validate behavior.

---

## 2. Non-negotiable rules

These are the security and privacy boundaries of the product. Breaking one is a
bug, regardless of how good the reason sounds.

1. **All navigation decisions go through `UrlPolicy`.**
   No `if (url.contains(...))` scattered elsewhere. No exceptions in UI code.
   If a URL needs a new rule, add it to `UrlPolicy` and to the route table in
   `SPEC.md`.

2. **Deny by default.** A host or route not explicitly allowed is blocked.
   Never write an allow rule that is a wildcard over `instagram.com/*`.

3. **Never allow a non-http(s) scheme.** `intent://`, `instagram://`, `fb://`,
   `market://`, `mailto:`, `tel:`, `whatsapp://` are always cancelled. Launching
   an external app is out of scope and defeats the purpose of the app.

4. **Never handle credentials.** Do not read, log, autofill, or inject into
   password fields. Do not add a native login form. The WebView's own session is
   the only auth mechanism. `CookieManager` is used for exactly two things:
   keeping the session alive and clearing it on user request.

5. **No network calls of our own.** No telemetry, no analytics, no crash
   reporting, no remote config, no "check for updates". The only HTTP traffic in
   the app is Instagram's.

6. **No third-party dependencies without a written justification** in
   `PROGRESS.md`. The dependency surface is deliberately tiny. A package must
   earn its place; "it's convenient" is not a justification.

7. **The DOM layer is cosmetic; the URL layer is the guarantee.**
   Anything that depends on an Instagram CSS selector must degrade gracefully
   when the selector stops matching. Never let a cosmetic failure crash the app
   or leave the user on a blocked surface.

8. **The reels guard is best effort.** Never describe it as guaranteed. Never
   remove the `block` fallback mode. The in-DM reel viewer has no URL, so it
   cannot be regulated by `UrlPolicy` at all — it is detected and frozen inside
   the page. `SPEC.md` §5.3 and `PROGRESS.md` must both state this honestly.

---

## 3. Architecture at a glance

```
lib/
  main.dart                     bootstrap only: runApp + platform flags
  app.dart                      MaterialApp, theme, route to the browser screen
  core/config/app_config.dart   constants + compile-time flags (dart-define)
  core/logging/guard_log.dart   in-memory ring buffer of allow/block decisions
  navigation/
    url_policy.dart             PURE DART. classify(Uri) -> UrlDecision
    instagram_routes.dart       route constants and URL builders
  webview/
    browser_screen.dart         the WebView host and app chrome
    browser_controller.dart     wires WebView callbacks to UrlPolicy
    webview_settings.dart       settings factories (normal / focus mode)
    reel_guard.dart             detects and freezes the in-page reel viewer
  ui/                           debug, settings, common widgets
assets/
  css/hide_instagram_chrome.css every selector lives here, nowhere else
  js/guard_document_start.js    history patch + click interception
  js/guard_load.js              sanitizer, MutationObserver, reel guard
  test_site/                    fake Instagram pages for automated tests
```

Rules that follow from this layout:

- `navigation/*.dart` must stay **pure Dart**: no Flutter imports, no WebView
  imports, no I/O. They are the only files with meaningful unit tests.
- `url_policy.dart` is the **single source of truth** for allowed routes. The
  document-start JS guard gets its rules generated from this file, never
  hand-copied.
- The UI never builds an Instagram URL by hand. It calls
  `instagram_routes.dart`.
- There is no `reel_link.dart`. The M0 spike proved the in-DM reel viewer has no
  URL and exposes no permalink, so pinning a shortcode is impossible. Do not
  reintroduce shortcode parsing without new evidence.

---

## 4. Changing the DOM sanitizer

Instagram ships DOM changes constantly. When the UI leaks:

1. Reproduce on the emulator with the debug screen open (it shows the current
   URL and guard log).
2. Inspect via `chrome://inspect` (debug builds enable WebView debugging).
3. Add or fix the selector in `assets/css/hide_instagram_chrome.css` only.
4. If a node must be *removed* rather than hidden, add it to the removal list in
   `assets/js/guard_load.js`.
5. Bump the `sanitizer version` comment at the top of the CSS file and note the
   change in `PROGRESS.md` with the date.
6. Verify that a **failed selector does not break the page**. The sanitizer must
   never throw.

Prefer hiding via a stable attribute (`aria-label`, `role`, `href`) over
generated class names such as `x1i10hfl`. Generated classes change without
notice; semantic attributes usually survive.

---

## 5. Coding standards

- Dart 3, null-safe, `flutter_lints` clean. `flutter analyze` must report
  **zero** issues before a change is considered done.
- Format with `dart format`.
- Every file starts with a doc comment explaining **why it exists**, not what
  each line does. Every public class and method gets a doc comment.
- Prefer `const` constructors, `final` fields, and small widgets.
- No state-management package. `StatefulWidget` + `ValueNotifier` is enough.
  If you think you need more, raise it first.
- No `print`. Use the guard log / `debugPrint` behind `kDebugMode`.
- Keep changes surgical. Do not reformat, rename, or "clean up" files unrelated
  to the task.
- Comments explain intent and constraints. Do not narrate obvious code.

---

## 6. Testing requirements

Three layers, all must pass before a milestone is called complete:

| Layer | What it covers | Command |
| --- | --- | --- |
| Unit | `UrlPolicy`, `ReelLink`, route builders. Fast, no device. | `flutter test` |
| Widget | Shell chrome, blocked notice, error view, back-button policy. | `flutter test` |
| On-device | Real Instagram behavior, reel focus mode, session persistence. | `flutter run` on the emulator, manual checklist in `SPEC.md` |

Rules:

- Every new allow/block rule needs a unit test on **both** sides: the allowed URL
  and its near-miss blocked sibling (e.g. allow `/direct/inbox/`, block
  `/direct/new/` if that is not a message surface).
- Widget tests must not touch the network or the WebView platform channel. Inject
  a fake controller behind an interface if needed.
- Automated on-device tests use `assets/test_site/` served by
  `InAppLocalhostServer`, never the live Instagram site. Real Instagram is
  manual-only because it needs a login.
- A manual test checklist lives in `SPEC.md`. Do not mark a milestone done
  without walking it.

---

## 7. Documentation duties

Four files must stay true. Updating them is part of the definition of done, not
an optional extra.

- `SPEC.md` — behavior and acceptance criteria. Update when a rule or route
  changes.
- `PROGRESS.md` — completed milestones, known breakage, captured selectors,
  next step. Update at the **end of every work session**.
- `MENTAL_MAP.md` — plain-English explanation for a non-developer. No code, no
  packages, no jargon. Update when the wiring changes.
- `AGENTS.md` — this file. Update only when a rule changes.

`PROGRESS.md` is written for an agent with no memory of the previous session.
Assume it starts from zero and needs to know what works, what is untested, and
what to do next.

---

## 8. Out of scope — do not build

- Push notifications
- Multiple accounts stored by us, or account switching UI
- Media download
- Native rendering of feeds, stories, or reels
- Anything that scrapes, caches, or proxies Instagram content
- Deep links into the app from outside
- Tablet or landscape-specific layouts
- iOS-specific work until an Android release exists

If a task seems to require one of these, stop and flag it.

---

## 9. Quick start

```bash
flutter analyze
flutter test
flutter run -d emulator-5554     # Android emulator only
```

Debug builds expose the debug screen (current URL, guard log, sanitizer report,
clear session). Release builds hide it entirely.
