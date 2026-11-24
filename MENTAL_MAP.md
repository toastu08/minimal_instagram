# MENTAL_MAP.md

A plain-English map of how Minimal Instagram works and how its pieces fit
together. No code, no framework names, no jargon. If something here is confusing,
that is a bug in this document — say so and it gets fixed.

---

## The one-sentence version

The app is a locked door into a single room of Instagram: your messages. The rest
of the building is still there, but you cannot walk into it.

---

## The three characters

Think of the app as three people doing different jobs.

**1. The Window**
It shows Instagram exactly as Instagram wants to be shown. Nothing is
re-created, nothing is copied. If Instagram changes its look tomorrow, the Window
shows the new look automatically. The Window has no opinions.

**2. The Doorman**
The Doorman stands at every door and checks where you are going before you get
there. He has a short list of places you are allowed to go — your message list, a
conversation, the login page. Everything else, he stops. He is the one who makes
the promise of this app real.

The Doorman is the most important character. Even if the decoration is broken and
a forbidden button is visible, pressing it still gets you stopped at the door.

**3. The Decorator**
The Decorator makes the room feel small. Instagram normally surrounds your
messages with a home button, a search button, a reels button, a profile button, a
row of stories, and a banner telling you to install the app. The Decorator covers
all of that up so it feels like a messaging app, not like Instagram.

The Decorator is allowed to be imperfect. If Instagram redesigns a page and the
Decorator covers the wrong thing for a day, you are still safe, because the
Doorman is still at the door.

---

## The journey of a tap

```
        You tap something
                |
                v
     +-------------------------+
     |  Doorman checks the     |  <-- happens BEFORE the page changes
     |  destination            |
     +-------------------------+
          |            |
     allowed        not allowed
          |            |
          v            v
   page changes    nothing happens,
   normally        small "not available" note
```

One detail worth knowing: Instagram does not always reload the page when you move
around. It often just swaps the contents, like a slideshow changing slides. So
the Doorman cannot only watch the front door — he also watches every internal
doorway. That is why there are three layers of checking, not one.

---

## What you can and cannot reach

| You try to... | What happens |
| --- | --- |
| Open the app | You land on your message list, never the feed |
| Tap a conversation | It opens normally |
| Read and send messages | Works normally |
| Scroll your inbox | Works normally |
| Tap home, search, explore, reels, profile | Nothing. Brief note. You stay put |
| Tap a story ring | Hidden, so there is nothing to tap |
| Tap a shared reel | That one reel opens, locked in place |
| Try to swipe to the next reel | Blocked at three levels |
| Tap a shared photo post | That one post opens |
| Tap a link that would open the Instagram app | Nothing. No other app opens |
| Get logged out by Instagram | You see the login page and can sign in again |
| Open the app days later | Still signed in, straight to your messages |

---

## The reel problem, explained honestly

This is the hardest part of the whole project, so it deserves a straight answer.

Instagram's reel viewer is not a page. It is a layer that appears on top of
whatever you were looking at, and it is designed for one thing: keep you
scrolling. There is no address to check, so the Doorman cannot help here. Instead,
three things stand between you and an endless reel feed:

1. **The spotter.** A small script inside the page notices when a video is filling
   the whole screen. That is what a reel viewer looks like from the inside.
2. **The collapse.** Instagram loads three reels at once — the one you are
   watching and its two neighbours — lined up in a strip. The app hides the two
   neighbours. With one left, there is nothing to scroll to, because the strip is
   exactly one screen tall.
3. **The freeze.** The app also tells the remaining strip not to accept scrolling
   or swiping.

If that fails on some future version of Instagram, the app has a fallback
setting: **Block reels**. In that mode a shared reel simply will not open. It is
less fun and completely reliable.

I will not pretend the collapse-and-freeze approach is a guarantee. It is a strong
deterrent. The honest status gets recorded as we test it.

---

## How the app remembers you

The app never learns your password. You type it into Instagram's own login page,
inside the window. Instagram then gives the window a badge that says "this is a
signed-in session". The app keeps that badge the way a browser keeps a cookie.

The app cannot read the badge, cannot copy it anywhere, and has no way to send it
to anyone. The only two things the app ever does with it are: keep it, and throw
it away when you press "Clear session".

---

## Where each part lives

| Part | Plain-English job |
| --- | --- |
| The startup file | Wakes the app up and hands control to the shell |
| The shell | Draws the top bar, back button, and the window itself |
| The rulebook | The Doorman's list. One file. Nothing bypasses it |
| The address helper | Knows the shape of Instagram addresses; builds them in one place |
| The page decorator | The stylesheet and script that cover up Instagram's furniture |
| The watch log | A rolling list of every door the Doorman allowed or refused |
| The motion | Gives opening or leaving a conversation a short slide, so it stops feeling like an instant jump |
| The hidden workshop | Debug-only screens, invisible in the version you would install |

---

## The state of things right now

The Doorman is on duty. The window opens straight to your messages, the app
remembers you between launches, and every attempt to reach the feed, explore, a
profile, settings or another app is stopped. This has all been tested by hand on
a real phone-sized screen.

The Decorator hides Instagram's "new message" pencil, because writing to someone
new is deliberately out of scope; leaving a button that always refuses would be a
dead end. Everything else on the messages screens is untouched.

The reel work is now live in its default shape. A reel shared in a conversation
opens on its own, with a small "Single reel" strip and a Close button. Swiping no
longer carries you to the next reel or throws you out of the viewer. Close, or
the phone's back button, puts you back in the conversation. The settings screen
also offers a strict mode, called **Block reels**, in which a shared reel simply
refuses to open and says so. That choice is remembered after the app is closed.

The sign-up door is shut as well. Instagram draws its "Create new account" flow
inside the sign-in page, without giving it an address the Doorman could check.
The app refuses the button itself and, if the flow still manages to appear,
returns you to the sign-in page. This is a strong deterrent, not a promise: it
depends on Instagram's labels, and a redesign could weaken it.

Opening a conversation used to be an instant jump, because Instagram's web
version does not slide from the message list into a chat. The app now adds a
short slide of its own: opening a chat brings the screen in from the right, and
going back brings it in from the left. It is decoration, not part of the lock on
the door. You can turn it off in Settings, and the phone's own "remove
animations" setting always wins.

Two honest notes. First, both the reel viewer and the sign-up flow belong to
Instagram and have no address of their own; the app's grip on them is strong but
not a guarantee, which is why the strict reel mode and the sign-up backstop
exist. Second, the settings screen can sign you out and wipe this app's Instagram
data; that has been tested by hand, including a fresh launch afterwards. After
clearing, the app is left signed out, ready for you to sign in again.

Signing in from the signed-out screen now ends in your messages. It did not
before: while signing in, Instagram briefly visits a page whose address changed
since the app was first built, and the Doorman stopped it, so the sign-in was
thrown back to the start. That whole family of Instagram sign-in pages is now
let through, and the route has been walked by hand, from the signed-out screen to
the messages list, including closing and reopening the app. The engineering notes
in `PROGRESS.md` record exactly what changed.

`PROGRESS.md` has the current status in engineering terms. This document will be
updated as each piece becomes real, and this section should never be more than
one step out of date.
