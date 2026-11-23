# SPEC.md

The behavior contract for Minimal Instagram. If the app and this document
disagree, one of them is a bug.

For change-handling rules see `AGENTS.md`. For current status see `PROGRESS.md`.
For a plain-English overview see `MENTAL_MAP.md`.

---

## 1. Product statement

Minimal Instagram is a Flutter app for Android that opens Instagram's website in
a WebView and exposes **Direct Messages only**. Every other Instagram surface is
either never reachable or bounces the user back to their inbox.

The app is a window, not a client. It does not reimplement Instagram, does not
store messages, and has no idea what the user's password is.

### Non-goals

- Home feed, Reels feed, Explore, Search, Shop, Notifications, Profile, Settings
- Story viewing (avatars and story rings are hidden)
- Account creation, account switching, multiple stored sessions
- Media download or offline caching
- Push notifications
- Any Instagram API usage of our own
- iOS, desktop, or web support

---

## 2. Platforms

| Platform | Status |
| --- | --- |
| Android | Supported, tested on an API 37 emulator |
| iOS | Scaffolding only, untested, no commitments |
| Linux / macOS / Windows / Web | Out of scope; must not be used to validate behavior |

Minimum Android version follows Flutter's default. The target device class is a
phone in portrait orientation. Tablet and landscape layouts are out of scope; the
WebView simply stretches.

---

## 3. Screens and states

The app has exactly three user-facing surfaces plus one developer-only surface.

### 3.1 Browser screen (the app)

A full-screen WebView with a thin app bar above it.

- **App bar**: back button, title ("Messages"), settings, reload, and a debug
  button in debug builds only.
- **Settings** (bottom sheet): reels behavior, clear session, About/version.
- The WebView fills the rest of the screen. Instagram's own navigation bars are
  hidden by the sanitizer, so the app bar is the only chrome the user sees.

States the screen must handle:

| State | Trigger | Behavior |
| --- | --- | --- |
| Loading | Cold start, reload | Progress indicator over a neutral background |
| Ready | Page loaded | WebView in full view |
| Offline / network error | `onReceivedError` for the main frame | Full-screen message + Retry |
| Server error | 5xx on the main frame | Full-screen message + Retry |
| Blocked navigation | User hits a blocked route | Stay where they were + brief "Not available" notice |
| Reel/post focus | A single item is open | Focus banner with "Close" |
| Session expired | Instagram redirects to login | Login page, with a notice explaining why |

### 3.2 Settings

- **Reels behavior**: `Single reel` (default) or `Block reels`. Changing it takes
  effect immediately and is remembered across restarts. It is the only setting
  stored on the device.
- **Clear session**: deletes cookies and site data, then returns to the login page.
- **About**: version, and a plain statement that this is an unofficial wrapper.
- **Debug info** (debug builds only): current URL, guard log, sanitizer report.

Settings persist across restarts. Only the reels choice is stored; nothing about
the user or the session is.

### 3.3 Debug info (debug builds only)

- Current URL and last 200 guard decisions
- Sanitizer report: how many nodes each rule matched in the last pass
- Selector version currently loaded
- Clear session, copy report to clipboard

This screen must be compiled out of release builds.

### 3.4 Login

There is no native login screen. The user logs in on Instagram's own page inside
the WebView. The app never reads, stores, or autofills credentials.

---

## 4. Route policy

This table is the contract implemented by `lib/navigation/url_policy.dart`. Any
host or path not listed as allowed is **blocked**. Deny by default.

### 4.1 Decision types

| Decision | Meaning |
| --- | --- |
| `allow` | Navigate normally |
| `redirect` | Load a different URL instead (used for `/` and legacy DM paths) |
| `block` | Cancel the navigation and stay on the current page, with a notice |
| `external` | Cancel the navigation silently; never hand off to another app |

### 4.2 Hosts

| Host | Rule |
| --- | --- |
| `instagram.com`, `www.instagram.com`, `m.instagram.com` | Evaluated by path (below). `m.` is normalized to `www.` |
| Any other host | `block` |

Sub-resource hosts (CDNs, image and video servers) are untouched — they are not
top-level navigations, and blocking them would break the page.

### 4.3 Paths

| Path | Decision | Notes |
| --- | --- | --- |
| `/` | `redirect` → `/direct/inbox/` | Match on **path only**; post-login lands on `/?deoia=1` (observed in M0) |
| `/direct/inbox/` | `allow` | The app's home |
| `/direct/inbox` | `allow` | Instagram omits trailing slashes sometimes |
| `/direct/t/<threadId>/` | `allow` | A conversation |
| `/direct/requests/` | `allow` | Message requests are still DMs |
| `/direct/new/` | `block` | Recipient search; deferred, see §4.5 |
| `/accounts/login/` (+ variants) | `allow` | Needed to sign in |
| `/accounts/password/reset/` | `allow` | Needed to recover |
| `/auth_platform/`, `/auth_platform/codeentry/` | `allow` | Login and 2FA hand-off. Required: M0 showed a 2FA login goes through both |
| `/accounts/two_factor/`, `/challenge/` | `allow` | Needed to pass Instagram's own checks |
| `/consent/` | `allow` | Cookie consent interstitial, shown once. Observed on a cold start (2026-11-23); blocking it leaves a blank page |
| `/accounts/signup/`, `/accounts/emailsignup/` | `block` | Account creation is out of scope |
| `/accounts/edit/`, `/accounts/logout/` | `block` | Profile editing and IG-initiated logout |
| `/reel/<code>/`, `/reels/<code>/` | conditional | Single-item mode only, see §5 |
| `/p/<code>/` | conditional | Single-item mode only, see §5 |
| `/reels/`, `/explore/`, `/explore/tags/…` | `block` | Feeds |
| `/stories/…`, `/stories/highlights/…` | `block` | Stories |
| `/accounts/activity/`, `/your_activity/`, `/settings/` | `block` | Account surfaces |
| `/api/…` and any navigated XHR endpoint | `block` | Never let the WebView *navigate* to JSON |
| Everything else | `block` | Deny by default |

### 4.4 Schemes

Anything that is not `http` or `https` is `external` and is always cancelled:
`intent://`, `instagram://`, `fb://`, `market://`, `mailto:`, `tel:`,
`whatsapp://`, `tg://`. The app never opens another application.

### 4.5 Deliberate restrictions (v1)

- **No new-conversation composer.** `/direct/new/` is blocked because it surfaces
  a global user search. Lifting this is a product decision, not a bug fix.
- **No Instagram login with Google or Facebook.** Those flows hand off to
  third-party identity pages that either block WebViews or leave our allowlist.
  Username + password only.
- **No logout from Instagram's UI.** Use Settings → Clear session.

### 4.6 Enforcement scope

The policy applies to **main-frame navigations only**: page loads, history
changes and in-page link clicks that replace what the user is looking at.
Sub-resource requests (images, video, scripts, XHR) and subframe navigations are
not policed.

This is safe because an iframe that navigates the top frame produces a new
main-frame navigation, which is judged normally. Subframes that stay subframes
cannot show the user a surface, so blocking them would break Instagram (login
and media playback in particular) without adding protection.

The rule is enforced in all three layers; see `PROGRESS.md` §9.

### 4.7 Surfaces with no URL

Instagram renders a few surfaces without changing the address. UrlPolicy is
blind to them by construction:

- the in-DM reel viewer (§5);
- the sign-up flow opened from the login page's "Create new account" control.

The sign-up control is a `div[role="button"]` with a React handler; the address
stays on `/accounts/login/` and no history entry is created (verified
2026-11-23). The in-page guard refuses the control on click, Enter and
pointer-down, using its `aria-label`. If the sign-up surface appears anyway, a
load-time backstop reloads the login page.

This is **best effort**, like the reel guard. Sign-up remains out of scope
(§4.5), and the URL rules still cover every address that exists.

---

## 5. Single-item viewing (reels and posts)

A DM can contain a shared reel or post. Tapping it must show **that one item and
nothing else**. Two modes, chosen in Settings.

### 5.1 Mode A: Single reel (default)

> **Revised after the M0 spike.** The original design assumed a reel link could
> be pinned by shortcode and that the viewer would reveal its URL. Neither is
> true. Verified: opening a reel from a DM produces **no URL change**, no
> history event, no dialog role, and no permalink for the active reel in the DOM.
> Focus mode is therefore structural, not URL-based. See `PROGRESS.md` §2.5.

1. The user taps a reel in a DM. The viewer opens as a full-screen overlay over
   the thread. It creates **no URL and no history entry**, so nothing below is
   URL-based.
2. The guard detects the viewer by looking for a `<video>` that covers at least
   60% of the viewport width and 50% of its height, and intersects the viewport.
   It is checked every 600 ms and on `DOMContentLoaded`.
3. **Two viewer shapes have been observed** and both are handled:
   - *Carousel*: three slides in one scroll container (the M0 spike shape). The
     guard hides every sibling slide around the active video, so `scrollHeight`
     equals `clientHeight` and there is nothing to scroll to.
   - *Single video*: one full-screen video with no scrollable ancestor
     (observed 2026-11-18). There are no slides to collapse; the guard freezes
     the video's own box instead.
4. The freeze blocks movement, not taps: a document-level capture `touchmove`
   handler calls `preventDefault`, and the container gets `touch-action: none`
   and `overscroll-behavior: contain`. A carousel also gets `overflow: hidden`.
   Taps must keep working so the user can use Instagram's own controls.
5. The check re-runs on every tick, because React may re-add slides or rebuild
   the overlay. Hidden siblings stay hidden for as long as the viewer is open.
6. A banner appears: "Single reel · Close".
7. Closing reloads the page underneath, which removes the overlay and returns to
   the same DM thread. Instagram's viewer has no close control the app can rely
   on, so the reload is the contract. Scroll position is not preserved; the
   thread reopens at its normal (latest-message) position.
8. Android back while the reel is open closes the reel; it does not leave the
   thread.

The guard reports `open`, `closed`, `blocked` (Mode B) and `freeze-failed`. If
the overlay is still visible 2 seconds after first detection and the freeze has
not been applied, the app treats focus mode as unreliable: it leaves the viewer
and shows "Reels aren't available in this mode". A transient failure while the
overlay is still mounting is normal and does not count.

### 5.2 Mode B: Block reels

Instagram does not expose the reel's permalink in the message DOM, so Mode B
cannot pre-screen every reel. It works on the same detection as Mode A: when the
viewer is detected, it is immediately closed and a notice is shown, and the
thread is restored. This is the guaranteed-safe option and must always work.

### 5.3 Honest limitation

Mode A is **best effort**. Instagram's viewer is a client-side overlay with no
address of its own, and its DOM is not a public contract. We defend with
structural collapse (when there is a carousel), gesture freezing, and re-checking
on every tick, but we cannot guarantee that a determined user on a future
Instagram build cannot reach a second reel. This is recorded here and in
`PROGRESS.md`, and Mode B exists precisely because of it.

What M5 actually verified on device (2026-11-18, Mode A): the overlay opened, the
banner appeared, swiping up and down neither advanced to another reel nor closed
the viewer, "Close" returned to the thread, and Android back left the reel
without leaving the thread. Two limitations are known and accepted:

- The viewer sometimes mounts a single video rather than a carousel. In that
  shape there is nothing to collapse, so the guarantee is weaker: only gestures
  are blocked. The `[mi-reel]` console log records which shape was seen.
- A viewer that Instagram renders outside the reach of the document-level touch
  handler (for example inside a closed shadow root) would not be frozen. None has
  been observed; Mode B remains the answer if one appears.

---

## 6. Interaction rules

### 6.1 Back button

Android back must never exit the app from a deep page, and must never reveal a
blocked surface.

```
if (reel/post focus is active)      -> exit focus, return to thread
else if (WebView canGoBack and
         current URL is a thread)   -> goBack()
else if (current URL is not inbox)  -> load inbox
else                                -> exit the app
```

### 6.2 Blocked-navigation feedback

Blocking is silent by default except for a short, non-blocking notice
("Not available in Minimal Instagram"). Repeated blocks within 2 seconds collapse
into one notice so the user is not spammed.

### 6.3 Pull to refresh

Not implemented. Reload lives in the app bar.

### 6.4 Links opening new windows

`target="_blank"` and `window.open` are denied. No secondary WebView is ever
created.

---

## 7. Session behavior

- Cookies and site data live in the WebView's own store. The app does not read
  them.
- A session survives app restarts and app upgrades.
- On cold start: if a session exists, land on `/direct/inbox/`; otherwise land on
  `/accounts/login/`. Redirecting `/` handles this naturally.
- Instagram may invalidate a session at any time; the app must not crash or loop.
  The login page is always an allowed destination.
- "Clear session" deletes cookies and site data, then loads the login page.
  It must confirm first.

---

## 8. Cosmetic sanitizer

Instagram's own navigation, stories tray, and extraneous chrome are hidden.

> **Scope reduced by the M0 spike.** DM pages render **no global navigation at
> all** — they are already full-screen messaging interfaces. The bottom nav only
> exists on the feed, which this app never loads. On a DM page,
> `div[role=navigation]` is Instagram's own DM top bar (Back / New message) and
> **must not be hidden**. See `PROGRESS.md` §2.3.

- All selectors live in `assets/css/hide_instagram_chrome.css`, except removal
  rules in `assets/js/guard_load.js`.
- Hiding is cosmetic. It must never be the only thing preventing access to a
  surface; that is `UrlPolicy`'s job.
- If a selector stops matching, the app must remain usable. The sanitizer never
  throws and never blocks page load.
- The sanitizer is versioned. Changing it requires a `PROGRESS.md` entry.
- Only semantic attributes (`role`, `aria-label`, `href`, `name`) may be used as
  selectors. Instagram's generated class names are content-hashed and change on
  every deploy.

What is hidden in v1:

| Element | Treatment |
| --- | --- |
| Global bottom nav | **Hidden structurally where it renders.** DM pages never render it; the standalone post page (`/p/<code>/`) does. It has no semantic attribute, so `guard_load.js` finds the fixed wrapper around its `/explore/` and `/reels/` links and hides that wrapper. UrlPolicy already refuses those destinations |
| Stories tray / story rings | Hide where present; not observed on DM pages in M0 |
| "New message" pencil (`a[href$="/direct/new/"]`) | **Hidden.** The composer is deliberately blocked (§4.5); leaving a button that always refuses is a dead end |
| "Open in app" banners and install prompts | Hidden structurally where present (the post page renders a "Use the app" banner) |
| Cookie consent | Shown once, never auto-accepted; hidden after the user answers |
| Notes tray and call buttons | **Left visible** (explicit product decision) |
| Sender avatars / profile links | Left visible; navigation is blocked by `UrlPolicy` |

The sanitizer is loaded at document start as part of the same injected bundle as
the navigation guard, so there is no flash of unfiltered chrome. It exposes
`window.__miSanitizerReport()`, which the debug screen prints: sanitizer version,
whether the stylesheet is injected, and the live match count for every selector
parsed out of the CSS file. The report is generated from the CSS text itself, so
it cannot drift from the stylesheet.

A selector that matches nothing on the current page is normal, not a failure: the
rules are written for any DM page, and no single page contains every element.

---

## 9. Milestones

Each milestone is shippable on its own and must pass its acceptance criteria
before the next one starts.

### M0 — Feasibility spike

Throwaway single screen that loads Instagram and reports what the DOM looks like.

**Acceptance:** login page renders in the WebView; a real password login
succeeds; `/direct/inbox/` renders; a DM thread renders; the DOM probe reports
the navigation, stories, and dialog selectors; we know whether opening a reel
from a DM changes the URL. Findings recorded in `PROGRESS.md`.

### M1 — Skeleton and pure core

Project structure, `UrlPolicy`, `InstagramRoutes`, and their tests. The
`ReelLink` / shortcode parser planned here was dropped in M5: the in-DM viewer
has no permalink. No WebView behavior yet.

**Acceptance:** `flutter analyze` clean; `flutter test` covers every row of §4.3
including near-miss URLs; no Flutter imports inside `lib/navigation/`.

### M2 — Enforcement

WebView host with the URL policy wired into navigation, history changes, and a
document-start click guard. Blocked notice, error view, back button, reload.

**Acceptance:** manual checklist §10.1 passes; attempt to reach feed, explore,
profile, settings, and an `instagram://` link — each is refused and the user
stays put.

### M3 — Sanitizer

Chrome hiding via CSS and the load-time guard, with a matching report.

**Acceptance:** manual checklist §10.2 passes; the sanitizer report lists every
selector in the stylesheet with a live match count and reports the stylesheet as
injected; disabling the CSS file does not break navigation.

### M4 — Login and session

Landing redirect, session persistence, expired-session recovery, clear session.

**Acceptance:** manual checklist §10.3 passes, including a full app kill and
relaunch.

### M5 — Single-item focus mode

Shortcode extraction, focus mode, escape detection, return to thread, and the
Mode B fallback.

**Acceptance:** manual checklist §10.4 passes in Mode A; Mode B blocks reels
completely; `PROGRESS.md` records whichever Mode A guarantees did not hold.

### M6 — Settings, debug, polish

Settings persistence, debug screen, app label, release manifest permissions,
release build smoke test.

**Acceptance:** a release build runs the manual checklist §10.5; debug screen is
absent from release; `INTERNET` permission present in the merged release
manifest; the reels choice survives a cold start; the app label reads
"Minimal Instagram".

### M7 — Automated regression

Local fixture site emulating Instagram routes, served by `InAppLocalhostServer`,
driven by an integration test.

**Acceptance:** `flutter test integration_test` passes on the emulator;
`flutter analyze` and `flutter test` clean; all four documents current.

---

## 10. Manual test checklists

Run these on the Android emulator, on a real account, before marking a milestone
complete. Real Instagram is manual-only because it requires a login.

### 10.1 Navigation (M2)

- [ ] Cold start lands on the inbox, not the feed
- [ ] Tapping a thread opens it
- [ ] Editing the URL is impossible, but an injected navigation to `/` lands on the inbox
- [ ] Injected navigation to `/explore/` is refused and the page does not change
- [ ] Injected navigation to `/reels/` is refused
- [ ] Injected navigation to a profile (`/<username>/`) is refused
- [ ] Injected navigation to `/accounts/edit/` is refused
- [ ] An `instagram://` link does nothing and no other app opens
- [ ] Back from a thread returns to the inbox
- [ ] Back from the inbox exits the app
- [ ] Reload preserves the current page

### 10.2 Sanitizer (M3)

- [ ] Inbox shows no bottom navigation and no left sidebar
- [ ] Inbox shows no stories tray or story rings
- [ ] The "New message" pencil is not visible in the inbox or in a thread
- [ ] The space where the pencil was does not leave a visible gap
- [ ] Inbox shows no "Open in app" or install banner
- [ ] Thread shows no top-level feed icons in the app bar area
- [ ] Debug → Sanitizer reports `styleInjected: true` and lists the stylesheet's
      selectors with their match counts (a count of 0 is normal on a page that
      has no such element; -1 means an invalid selector), plus `chromeHidden`
      (0 on DM pages, 2 on a post page with the tab bar and install banner)

### 10.3 Session (M4)

- [x] Log in with username + password; 2FA works if enabled
- [x] Kill the app from the task switcher, relaunch: still logged in, on inbox
- [x] Clear session returns to login and does not keep the old page in history
- [ ] An expired session lands on login without a crash or redirect loop

The clear-session path was walked on 2026-11-23. Two details belong in the
record: after clearing, Instagram first shows its cookie-consent page again
(cookies were deleted), and declining it lands on the login page. Pressing back
from login does not reveal the old thread (history was cleared); it reloads the
login page. A cold restart stays on login.

Expiry was not observed in a real session; the code path is unit-visible but the
device checklist item stays open until it happens or is simulated deliberately.

### 10.4 Single item (M5)

- [x] Open a reel from a DM: it plays, and it is the only reel reachable
- [x] Swiping up does not advance to another reel
- [x] Swiping down does not dismiss the viewer
- [x] The "Single reel · Close" banner appears over the viewer
- [x] Closing returns to the same thread (scroll position resets to the bottom)
- [x] Android back while the reel is open leaves the reel, not the thread
- [x] Keyboard/media "next" affordances are absent or inert
- [ ] Open a post from a DM: it is visible and does not open a feed
- [x] Mode B: tapping a reel shows a notice and nothing opens
- [x] The app is not stuck in focus mode after a network error or
      background/foreground cycle

Checked items were walked on `emulator-5554` on 2026-11-18 and 2026-11-23.
"Keyboard/media next" was checked by sending `KEYCODE_MEDIA_NEXT`,
`KEYCODE_DPAD_DOWN` and `KEYCODE_PAGE_DOWN` while a reel was open: the reel did
not change and the viewer stayed open.

The post item is still open because the test thread has no post attachment. A
standalone `/p/<code>/` page was verified separately: it renders as a single
"Post" view with no feed, and the global tab bar and install banner are now
hidden (sanitizer v2). The DM-attachment path itself has not been walked.

### 10.5 Release build (M6)

- [x] `flutter build apk --release` succeeds
- [x] The APK installs on a clean emulator; the launcher label reads
      "Minimal Instagram"
- [x] Cold start reaches Instagram (proves `INTERNET` is in the release manifest)
- [x] No debug button and no guard/sanitizer screens in the release build
- [x] A blocked route shows "Not available in Minimal Instagram"
- [x] Tapping "Create new account" on the login page stays on the login page
- [x] Settings → Reels choice survives a cold restart
- [x] Clear session from the release build returns to the login page

Checked on device on 2026-11-23; see `PROGRESS.md` §14. The first run failed the
"Create new account" item: the sign-up flow is rendered client-side with no URL
and slipped past the URL layers. It is now refused by the in-page guard, with a
reload backstop.

---

## 11. Known limitations

1. **Reels focus mode is best effort** (§5.3). The viewer has no URL of its own,
   so it cannot be regulated by the route policy at all. Mode B exists for this
   reason.
2. **The client-side sign-up flow is blocked best-effort** (§4.7). It renders
   inside the login page without a URL; the app refuses its labelled controls and
   reloads if the surface still appears. A changed label or marker can defeat the
   DOM layer.
3. **DOM-dependent hiding breaks when Instagram ships a redesign.** The app stays
   usable; some chrome may reappear until selectors are updated.
3. **Google and Facebook login do not work** inside a WebView.
4. **Instagram may challenge an unfamiliar login.** This is Instagram's security
   system, not an app bug.
5. **No push notifications.** New messages require opening the app.
6. **Voice and video calls may not work** inside a WebView (camera/microphone
   permissions and WebRTC support). Their buttons are left visible by design;
   whether they function is a known unknown recorded in `PROGRESS.md`.
7. **Session invalidation is outside our control.** Instagram can log the user
   out at any time.
