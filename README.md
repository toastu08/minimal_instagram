# Minimal Instagram

An Android app that hosts Instagram in a WebView and exposes **only Direct
Messages**. The feed, Explore, Reels feed, profiles, settings and stories are
unreachable; a shared reel opens as a single item, never a feed.

The app never sees or stores your credentials. Sign-in happens inside the
WebView, on Instagram's own pages.

> Unofficial and unaffiliated with Instagram or Meta.

## Read first

| File | What it is |
| --- | --- |
| `SPEC.md` | What the app must do, route policy, milestones, test checklists |
| `PROGRESS.md` | Current state, findings, delivery notes for the next session |
| `AGENTS.md` | Rules for changing the project |
| `MENTAL_MAP.md` | Plain-English explanation with no code |

## Quick start

```bash
flutter analyze
flutter test
flutter run -d emulator-5554     # Android emulator only
```

A release build is `flutter build apk --release`. Release builds hide the debug
screen and require the `INTERNET` permission declared in the main manifest.

## Scope

Android only. iOS scaffolding exists but is untested. Desktop and web are out of
scope.
