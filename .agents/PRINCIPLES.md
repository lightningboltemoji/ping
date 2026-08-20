# Ping — persistent effects for macOS notification badges

A **Swift**-based menu bar agent that turns a notification badge into something you cannot miss. This
document is the _what_ and the _why_: the model, the charter, the thesis, and what Ping owes the person
using it. `IMPLEMENTATION.md` is the _how_ — boundaries, loops, invariants.

**The keep/cut test for this file: would changing it change what Ping _is_?** Mechanism belongs next
door. The investigation, the rejected alternative and the number that settled an argument belong to
`changes/`.

---

## 1. The model

- **A badge is state; a notification is an event.** A macOS notification arrives, is missed, and is
  gone. The badge it leaves on the Dock is the same fact held still, and the badge is what Ping reads.
  Persistence is therefore not something Ping adds to the notification system — it is a property of the
  Dock that Ping borrows, which is why Ping needs no history, no store and no database, and why
  restarting it loses nothing.
- **The Dock is the sensor.** Ping never sees a notification. It sees what the Dock is showing about an
  app, once per poll, and everything on screen is a function of that reading, the config file, and what
  the user last clicked.
- **The alphabet is three symbols per app: nothing, a bare dot, a count.** No sender, no content, no
  timestamp, no per-notification identity — the Dock does not have those to give. **Scope is bounded by
  the sensor**: anything needing to know what a notification _said_ cannot be built here, and that is a
  keep/cut test for a feature request rather than a shortcoming to apologise for.
- **An app is its Dock title.** `[apps.Slack]` is the string under the icon — the user's own vocabulary,
  localised, and occasionally not what AppKit calls the same app, which is the entire reason `bundle-id`
  exists as an escape hatch.
- **An effect is a subscription, and the file is where you subscribe.** Absence never means "off"; it
  means "not signed up". A Ping with no config file puts nothing whatever on screen — **Ping ships
  silent** — for the reason a window manager ships with no default keybindings: an effect nobody asked
  for is on somebody's screen.

**The order of the two goods.** If what is glowing is not what is badged, we have failed. If it is
_also_ calm enough to work through, we have won. Everything about the gradient is the second win, and
none of it may become load-bearing for the first.

---

## 2. The charter: read-only, through the Dock

**The Accessibility API on `com.apple.dock` is the only way in, and Ping uses it in one direction.**

macOS publishes no system-wide notification state. `UNUserNotificationCenter` answers only for the
process that asks it, and there is no public route to "which applications are unread". The Dock renders
that answer for everybody, and its accessibility tree is where it can be read: a Dock item's
`AXStatusLabel` is absent, `""` for a bare red dot, or digits for a count. That is the whole interface,
and there is no second one to fall back to.

- **It is a read, never a write.** There is no `AXUIElementSetAttributeValue` and no
  `AXUIElementPerformAction` anywhere in the tree. Ping never clears a badge, never dismisses a
  notification and never touches another application. Kill it mid-flight and the desktop is exactly as
  it was — the badge is still there, the app is still unread, and the only thing gone is the glow.
  Acknowledging dismisses **the effect, not the notification**, and that distinction is the charter
  rather than a detail of the menu.
- **It is a poll, and the poll is forced rather than chosen.** A Dock item accepts observer registration
  for `AXCreated` and `AXUIElementDestroyed` and refuses every notification that could carry a value
  change, `AXValueChanged` among them; a badge set, changed and cleared produces no callback at all.
  What the Dock _does_ do is update its own tree within about 5 ms of an app setting a badge — so the
  sensor is instant and **`poll-interval-ms` is the whole of Ping's latency**. Sampling is the only
  thing standing between a notification and its effect, and it is a number the user owns.
- **The grant is mandatory, and its absence is silent.** Without the Accessibility grant the read
  returns nothing and raises no error — indistinguishable from a desktop where nobody has a badge. So it
  is asked for in a window at first launch and watched until it lands, because a Ping that quietly
  notices nothing is the worst failure available to it.
- **The whole toolbox**, stated so that adding to it is a decision: AX reads of one process, our own
  borderless `NSWindow`s, Core Animation on layers we own, `NSWorkspace` for icons and the frontmost
  app, and `SMAppService` for launch-at-login. No private symbol, no injection, no SIP concession, and
  no code in anybody else's process.
- **What the charter costs, once.** Accessibility rules out the sandbox, which rules out the Mac App
  Store: Ping is installed and granted deliberately, by somebody who wanted it.

---

## 3. The thesis: amplify, never intercept

Ping is a **second, louder channel over a signal macOS already publishes**, and it is only ever
additive.

|                     | macOS                          | Ping                                             |
| ------------------- | ------------------------------ | ------------------------------------------------ |
| **shows**           | a banner, then a badge         | an effect, for as long as the badge lasts        |
| **where**           | a corner, and the Dock         | the edge of your visual field                    |
| **for how long**    | seconds, then small and quiet  | until you have dealt with it, or said otherwise  |
| **owns the signal** | the app, and the Dock          | nothing — Ping only reads                        |

Five consequences, and they are the whole design:

- **It must be visible without being read.** The failure Ping exists to fix is a small, low-contrast
  badge in the middle of a screen you are looking straight through. The answer is area, slow motion and
  the _periphery_ — a gradient across a whole screen edge, breathing over a couple of seconds — because
  those are what the eye catches without being pointed at them. That is the bar a future effect clears:
  noticeable at a glance nobody intended to take, and legible without focusing on it. The three
  effects divide it between them: the **glow** is area and no identity, and says _something_; the
  **notch** is identity without detail, and says _who_, in the one strip of screen that is already
  dead space; the **shelf** is detail — icons, names and counts — and says _what and how much_.
- **An edge holds one glow at a time, so contention is resolved in time rather than in space.** Two
  apps on the same edge do not get half each — they take turns, the newest first, crossfading between
  them. The pulse follows from that and is deliberately **global**: two apps sharing an edge and
  breathing at different rates is not one effect, it is two fighting over the same pixels. The notch
  answers the same way when more apps are badged than its last slot can hold, and for the same
  reason: an effect that dropped one would under-report the Dock rather than share the room.
- **Persistence is the product, so every exit is load-bearing.** An effect that will not go away is the
  failure mode, so there are four ways out and each answers a different question. **Acknowledge** is _I
  have seen it_ — a statement about a count, so a badge that grows past what you acknowledged is new
  again, and one that falls and climbs back is new again too. **Snooze** is _not now_.
  **Suppress-when-focused** is _not for the thing I am already looking at_. The **master switches** are
  _not this, ever_. The first two are one click from the menu bar, because an exit you have to open a
  window to reach is not one.
- **Ping owns no input.** Every window it puts on screen is borderless, click-through and unfocusable;
  no chord is registered anywhere on the machine; nothing is ever raised over your work that has to be
  dismissed; nothing makes a sound. **Ping cannot be in your way** — and the price, that it cannot be
  talked to either, is paid at the menu bar and in the file.
- **Nothing on screen is remembered; all of it is derived.** One pure function takes the config, the
  Dock's reading and what the user last clicked, and answers with everything that should be drawn;
  renderers are told rather than asked. Which is why **a preview is not a mode**: the settings window
  previews by handing that same function a synthetic reading of the Dock and the config it _would_
  save, and no renderer knows the difference. A preview that were a second code path could disagree
  with the real thing about what a setting does, and this one cannot.

---

## 4. What Ping owes the user

- **What is glowing is what is badged, right now.** Each poll is a whole reading of the Dock rather
  than a diff against the last one, so Ping holds no opinion of its own about your notifications and
  cannot drift from them. The only thing it remembers between polls is what you acknowledged, and that
  is remembered in the Dock's own spelling.
- **Nothing on your screen that you did not write down.** An app absent from the file gets nothing; an
  effect absent from an app gets nothing. Defaults describe how an effect looks once you have asked for
  it, never whether you asked.
- **An effect you cannot escape is a bug.** Whatever else has failed, the menu bar acknowledges and
  snoozes, and the file's master switches take an effect off the screen wholesale.
- **You are informed, never interrupted.** No sound, no focus taken, no click intercepted, no banner to
  dismiss. The effect competes for your peripheral vision and deliberately loses every contest with
  your work.
- **The effect belongs to a screen, not to a space.** Switching to a full-screen app does not take it
  away, because the notification you miss is exactly the one that arrives while you are full-screen.
- **Configuring Ping is editing its file, and the settings window is a second way to do that rather
  than a second authority.** It reads the file, writes the file, and tells the running app nothing —
  the file watcher does the rest, so the window and the desktop cannot come to hold different opinions.
  It splices single values and never rewrites: Ping is configured by hand, and the comments, the
  ordering and the blank lines that group one app from the next are the author's work. Writing a value
  that is already the default takes the line out rather than pinning it. A file it cannot parse does
  not open it at all — the window says so and the file is one click away — because splicing text whose
  meaning is unknown is the one thing a GUI must not do, and a config that will not parse is the one
  most worth editing by hand.
- **Edits show before they are saved, and the window says which is which.** Every control puts its
  change on the screen at once; Save only decides whether it persists. That is what makes Discard mean
  something, and it is why the tab in front badges the apps it is about rather than making you wait for
  a real notification to arrive.
- **Neither editor clobbers the other.** The file is watched while the window is open: a change arriving
  on a draft with nothing unsaved is a silent re-read, and one arriving on a dirty draft is reported
  rather than applied, with both ways out offered and Save held until one is taken. Throwing away
  typing is worse than either version of the file.
- **A config that is wrong is an error, not a silent shrug.** Missing means every default, because Ping
  must run before it is configured. An unknown key is an error naming its line, because a Ping that
  quietly ignores `colour` is one the user believes is broken. And a file that stops parsing changes
  **nothing** — the last good config stays on screen and the menu bar says why — because taking every
  effect off the screen as the side effect of a typo is the worst available response to one.
- **One reader behind both surfaces.** `ping-dot-app validate` says exactly what the app itself would
  say about your file, out of the same code, and the CLI ships inside the bundle so there is only ever
  one copy of it on the machine.

---

## 5. Constraints (truths, not bugs)

- **There is no public, system-wide notification state.** Every route that exists answers about the
  calling process. The Dock's accessibility tree is not the best of several options; it is the only one,
  and this is _the_ constraint that shapes §2.
- **The Dock announces nothing.** A Dock item refuses observer registration for value changes, and a
  badge appearing produces no callback. Polling is not a simplification we chose and might later
  remove — it is the only mechanism on offer, which is what makes the interval a first-class setting
  rather than an implementation detail.
- **`AXStatusLabel` is a presentation string, not a model.** It is what the Dock draws, so `""` is a
  bare dot and `"0"` is an app that drew a zero. Ping keeps it as the Dock's own string rather than
  parsing it into a number, because that is the only way the two stay distinguishable.
- **A Dock title is a user-facing string** — localised, changeable, and unique only by convention. It is
  nevertheless the key, because it is what the person writing the config can see. `bundle-id` exists for
  the one place a second opinion is available and matters: deciding whether the app you are looking at
  is the app that is badged.
- **A missing Accessibility grant reads as an empty Dock.** No error, no exception, no
  empty-versus-denied distinction — so the grant is asked about directly rather than inferred from a
  quiet reading.
- **A badge is per app.** Never per window, per space, per conversation or per notification. An effect
  can only ever be as specific as the app it is about.
- **Only the badge's owner can clear it.** Ping cannot mark anything read, and would not if it could —
  acknowledgement is Ping's own memory, held beside the Dock's and never written back into it.
- **The Dock is a process, and it can restart.** Every poll re-derives its application element from
  scratch, so a Dock relaunch costs one interval and needs no notice; an element cached across polls
  would be a stale port reporting an empty desktop forever.
- **A window on one space is invisible from another**, whatever its level, unless it is told to join
  them all. Both effects say so explicitly, and anything new that draws must.
- **Nothing here is CPU-bound.** The hot path is a handful of AX round trips at 2 Hz and a Core
  Animation gradient on a layer we own. There is no arithmetic worth optimising, and a smoothness
  problem would be a compositing question rather than a speed one.

---

## 6. Related implementations

- **[SketchyBar](https://github.com/FelixKratz/SketchyBar)** — the prior art this replaces for its
  author. Putting Slack's badge in the menu bar works, and it costs you the menu bar; Ping's premise is
  that the same signal can be made loud without moving anything you already rely on.
- **[Pock](https://github.com/pigigaldi/Pock)** — where the Dock traversal comes from, credited in
  `DockItem.swift`. It put the Dock on the Touch Bar and reads `AXStatusLabel` the same way, for the
  same reason: there is no other way to ask.
- **macOS Focus and Notification Center** — the counter-example, and a complement rather than a rival.
  Apple's answer to missed notifications is _fewer and quieter_; Ping's is _louder and persistent, for
  the few you chose_. Focus decides what gets through; Ping decides what happens to what did.
