# Ping — Implementation

**Companion to `PRINCIPLES.md`.** `PRINCIPLES.md` is the _why_ — the read-only charter, the badge as
state, what an effect owes the person looking at it. This document is the _how_: the boundaries, the
loops, the state, and the rules a change has to respect. Where the two disagree, `PRINCIPLES.md` wins on
principle and this document gets corrected.

**What is deliberately not here.** Rejected alternatives, the bug that motivated a line, the numbers
that proved it, the investigation — those live in `changes/<id>.md`, which `git blame` reaches
(`.agents/README.md`). This file carries only what someone needs in order to _contribute_: where a thing
goes, what holds the system together, and which invariants break the product if you break them.

Guiding bias, restated: **stay small.** Ping reads one string per app and draws with it.

---

## 1. The architectural spine

**One pure function decides everything on screen, and the renderers are told rather than asked.**

```
   ~/.config/ping/ping.toml ──► Config      ┐
                                            │
   Dock.app  ──[AX poll]──►  BadgeSnapshot  ├──► EffectResolver.renderState ──► RenderState
                                            │        (pure, no framework)          │
   menu bar · settings · frontmost ──► RuntimeState ┘                              │
                                                                                   ▼
                                                     GlowRenderer · ShelfRenderer · NotchRenderer
                                                                     (NSWindow / CA / SwiftUI)
```

Three invariants hold this together:

1. **`EffectResolver.renderState(config:snapshot:runtime:now:)` is the only place that decides what is
   drawn.** It is a pure function of four values and imports no framework, so the whole truth table is
   testable headless. A renderer that decided anything for itself would be a second opinion about a
   question §4 already answers.
2. **`RenderState` is a value, and renderers are dumb.** The interface is `render(_ state: RenderState)`
   — no renderer reads the config, the engine, or any observable. Adding an effect later is one renderer
   and one config section, and nothing else moves.
3. **`renderState` is computed, never stored.** `EffectEngine` holds three values and derives the fourth
   on every read, so there is no cache to invalidate and no way for what is on screen to be stale with
   respect to what produced it. Deduplication happens once, at the one place that watches it (§2), on
   `RenderState`'s own `Equatable`.

`EffectEngine` is the app's only `@Observable` object. Everything it holds — `Config`, `BadgeSnapshot`,
`RuntimeState` — is a `Sendable` value type.

---

## 2. The loops

`AppDelegate` (`Sources/Ping/AppDelegate.swift`) is the whole of the wiring: four `Task`s, each draining
one `AsyncStream`, plus one notification observer. There is no observation re-arming anywhere.

| Loop         | Source                                    | Does                                                       |
| ------------ | ----------------------------------------- | ---------------------------------------------------------- |
| **render**   | `Observations { engine.renderState }`     | dedupes on `!=`, then `glow.render(state)`, `shelf.render(state)`, `notch.render(state)` |
| **poll**     | `BadgeMonitor.snapshots(interval:)`       | `engine.apply(snapshot)` — folds the reading in, ages acknowledgements |
| **screens**  | `ScreenTopology.changes()`                | every renderer drops its windows and rebuilds               |
| **config**   | `ConfigLoader.changes()`                  | `engine.apply(result)`, then syncs launch-at-login          |

Two things outside the four:

- **Frontmost app** arrives as an `NSWorkspace.didActivateApplicationNotification` observer rather than a
  stream, because it carries its answer in `userInfo` and there is nothing to poll. It writes two fields
  of `RuntimeState` and is also read once at boot, so a Ping started while Slack is in front knows it.
- **Snooze expiry** is a `Task` inside `EffectEngine`. Nothing else would notice the moment a snooze runs
  out — no poll changes, no file changes, and `renderState` is only re-read when something publishes —
  so the engine wakes for it and clears the field itself.

**The interval is read through a closure**, not captured: `poll-interval-ms` changing under a running
loop takes effect on the next sleep rather than tearing the stream down.

**Two dedupes, at different altitudes.** `BadgeMonitor` yields only when the snapshot differs from the
last one, so a quiet desktop produces no traffic at all; the render loop then compares `RenderState`, so
a badge change that resolves to the same picture — an app the file does not mention, an acknowledged
count ticking under its ceiling — reaches no renderer.

---

## 3. Module graph & where things go

Three library targets and two executables. Dependencies point strictly upward.

```
PingConfig    pure — no AppKit, no NSColor: the TOML grammar, the schema table, the
    │         editable document, diagnostics, colours as RGBA.            (zero deps)
    ▲
PingCore      AppKit for AX and NSScreen only — dock reading, badge state, runtime state,
    │         the resolver, the config loader and its watcher.       (deps: PingConfig)
    ▲
PingUI        SwiftUI/AppKit — the effect windows and renderers, the settings window,
    │         the menu bar, onboarding, resources.          (deps: PingConfig, PingCore)
    ▲
   ├── PingApp        executable — @main; the four loops.      (deps: all three)
   └── ping-dot-app   executable — validate/explain.           (deps: PingConfig only)
```

Each boundary buys one enforced property:

- **`PingConfig` names no `NSColor` and imports no UI framework.** A colour is `RGBA` down here and
  becomes an `NSColor` in exactly one file, `PingUI/Color.swift`. That is what lets the resolver and the
  whole cascade be tested with no window server. The module graph cannot enforce it on its own —
  `PingConfig` links Foundation, and Foundation on macOS reaches a long way — so `ImportFenceTests`
  reads the sources with comments stripped and fails on `import AppKit`, `import SwiftUI`, `import
  Cocoa` or the string `NSColor`.
- **`PingCore` may reach AppKit, but only for AX and `NSScreen`.** The same fence forbids it SwiftUI and
  `NSColor`. This is the target that talks to the system and still deals in values.
- **`ping-dot-app` depends on `PingConfig` alone.** No AX, no AppKit, no engine — so it launches fast,
  and everything with logic in it is in a library a test can import.
- **Neither executable product is named for what it becomes.** `PingApp` becomes
  `Contents/MacOS/Ping`, because a product named `Ping` would collide with `ping` in the bin directory
  on a case-insensitive filesystem. `ping-dot-app` is a CLI name macOS has not already taken; it prints
  whatever `argv[0]` says, so a symlink called `ping` describes itself correctly.

**Where a new thing goes**, in the order to ask:

| If it…                                                    | it belongs in           |
| --------------------------------------------------------- | ----------------------- |
| is a fact about the config file's _text_ or its schema     | `PingConfig`            |
| decides _what should be on screen_                        | `PingCore/EffectResolver` |
| is a system reading — the Dock, the screens, the file      | `PingCore`              |
| is how something is _drawn_ or edited                     | `PingUI`                |
| only wires things together                                | `Sources/Ping/AppDelegate.swift` |

If a decision needs a system answer _and_ a policy, split it: `PingCore` reports the fact as a value and
the resolver decides what it means. The frontmost app (fact) versus `suppress-when-focused` (policy) is
the model case.

---

## 4. The cascade — how an effect resolves

The one piece of arithmetic in the product. A glow is four layers overlaid left to right:

```
ResolvedGlow.builtin  ⊕  [glow]  ⊕  apps.<App>.glow  ⊕  apps.<App>.glow.<count|dot>
```

- **Every key is optional at every level except the first**, and `nil` means _inherit_ rather than
  _off_. `GlowLayer` is the optional-everything shape; `ResolvedGlow` is the everything-answered shape a
  renderer receives. `overlaid(with:)` composes two layers; `applying(_:)` lands a layer on a resolved
  value.
- **The built-in floor** is `enabled: true, edge: .bottom, color: .green, size: 1.0, opacity: 1.0`. It
  exists so that `glow = {}` under an app is a complete, drawable answer.
- **`resolvedGlow(for:badge:)` returns `nil` three ways**, and they are different sentences: the master
  switch `[glow].enabled = false` is off wholesale; an app with no `glow` table never subscribed; a
  resolved `enabled == false` subscribed and then opted out. Only the middle one is _absence_, and
  keeping it distinct is what makes `PRINCIPLES.md §1`'s "an effect is a subscription" true in code.
- **Badge kind is the last word.** `count` and `dot` tables override the app's own layer and only for
  that kind, so `[apps.Messages.glow.dot] enabled = false` means _glow for a real count, stay dark for a
  bare dot_.
- **The shelf takes only `enabled` per app**, because the shelf is one shared object on one screen edge:
  a per-app anchor or padding would be several shelves disagreeing about where the shelf is.
- **The notch cascades the same way, one level shallower**, because there is no `[notch]` layer to
  inherit from — `[notch]` describes the *strip* rather than an indicator:

  ```
  ResolvedNotchItem.defaultColor  ⊕  apps.<App>.notch  ⊕  apps.<App>.notch.<count|dot>
  ```

  `NotchLayer` is the optional-everything shape and takes the two keys an indicator has of its own,
  `enabled` and `color`; the built-in floor is the Dock badge's red, so `notch = {}` is already
  legible. `style` is deliberately not per-app, for the shelf-anchor reason: indicators disagreeing
  about their own shape would be several notches. `resolvedNotch(for:badge:)` returns the same three
  `nil`s, and is also where `count` falls back to a `dot` for a badge that has no digits to draw.

`ResolutionTests` covers the whole table, one badge kind at a time.

---

## 5. Runtime state

`RuntimeState` is everything that varies while Ping runs and is never written to the file. It is a value
type, which is what keeps the resolver pure.

- **`snoozedUntil`** — a moment. `isSnoozed(at:)` takes `now` as an argument rather than reading the
  clock, so the resolver stays a function of its inputs.
- **`acknowledged: [String: String]`** — Dock title to the badge that was showing when the user
  acknowledged it, kept as **the Dock's own raw string**. That is what preserves the difference between
  `""` (a bare dot) and `"0"` (an app that drew a zero), which an `Int?` would lose.

  Three rules, and they are subtle enough to be tested rather than trusted (`AcknowledgementTests`):

  - A **count** stays covered while it is at or below what was acknowledged; a bare dot is covered by a
    bare dot; a count arriving after a dot is new, and so is a dot arriving after a count — a different
    kind of badge, not a smaller one.
  - `reconcile(with:)` runs on **every** snapshot: a badge that disappeared forgets its
    acknowledgement, a badge that _fell_ is followed down (so climbing back to the old level is new
    again), and a badge that grew past its ceiling drops the acknowledgement entirely.
  - Acknowledging takes everything currently badged, in one gesture, from the menu bar.

- **`frontmostAppName` / `frontmostBundleID`** — both, because `NSRunningApplication.localizedName` and
  the Dock title usually agree and are not guaranteed to. An app that declares `bundle-id` is matched on
  that; everything else falls back to the name.
- **`preview`** — §6.

---

## 6. The preview

An open settings window changes **two** things about what is drawn, and they are separate on purpose.

- **`EffectEngine.previewConfig`** answers _drawn from which config_: the draft's reading of the file it
  _would_ write. `effectiveConfig` prefers it, so a colour chosen in the window is on screen before Save,
  and closing the window clears it — which puts the saved file back with nothing having to remember what
  it said.
- **`RuntimeState.preview: EffectPreview?`** answers _drawn for whom, and which effect_: a synthetic
  `BadgeSnapshot`, a `PreviewEffects` scope, and stand-in apps.

Rules the resolver enforces:

- A preview **bypasses every suppression** — no snooze, no acknowledgement, no focus suppression. The
  user is asking to see a setting, so the settings alone decide.
- A preview is **scoped**: the Glow tab may not put a shelf on screen. Anything outside `effects` stays
  dark whatever the config says. A preview about the notch alone is the one that also *adds* something:
  it gets the strip whatever `always-show` says, because a Notch tab previewing an empty screen is
  precisely the thing a preview must not be.
- **Stand-ins are only ever added.** An app the file already describes is drawn the way the file
  describes it, so a preview cannot quietly contradict the config it is previewing. Stand-ins exist for
  the case where nobody is subscribed to the effect being edited — otherwise the shelf settings would
  preview an empty screen.
- `isPreview` makes every renderer draw on the main screen only, whatever `monitors` says: a preview
  answers to the window, and the window is on one screen.

**The preview follows the window, not the pointer** (`SettingsModel.pushPreview`). Four bound values —
the tab, the selected app, the hovered row, the badge kind — each push on `didSet`, so the preview is
rebuilt on every edit as well as on every move. A hover-only preview died the moment the pointer reached
the control it was previewing.

---

## 7. The effects

All three renderers hold their windows in a dictionary keyed by what would invalidate them, keep the
last `RenderState` they were given, and rebuild from it on `screenParametersChanged()`.

Every window is borderless, `ignoresMouseEvents`, shadowless, and
`collectionBehavior = [.canJoinAllSpaces, .stationary]` — an effect belongs to a screen, not to a space
(`PRINCIPLES.md §4`), and a window that stays on its origin space vanishes into a full-screen app. The
notch's adds `.fullScreenAuxiliary`, because the strip hangs in the menu bar's own furniture. None is
ever made key.

### 7.1 Glow

- **One window per `(displayID, edge)`.** Glows are grouped by edge, and a window is handed every glow
  landing on its edge — the rotation between them is the view's problem, not the renderer's.
- **`Rotator`** is the LRU both effects share: new entries go to the front, survivors keep their order,
  and `next()` moves the current one to the back. If what is on screen disappears from the set, the
  next one is pulled up immediately.
- **`GlowView` is the animation state machine**, four phases driven by `CAAnimationDelegate`
  callbacks: `fadeIn → fadeOut → (crossfade | fadeIn) → …`. With one glow that is a breath; with several
  it is a breath and a handover. A glow removed mid-animation gets an accelerated fade-out proportional
  to how bright it currently is, so a badge going away does not wait out a full cycle.
- **The pulse is global** (`[glow.pulse]`), and `setPulse` takes effect on the _next_ animation, so a
  config reload never cuts one short.
- **Geometry.** The window is a slab `depth` (0.25) of the screen's **height** deep, on whichever edge —
  so a left or right glow's width is a fraction of the screen's height rather than its width. The
  gradient is radial, with start and end points derived from the edge and `size`.

### 7.2 Shelf

- **One window per display**, `.statusBar` level, hosting a SwiftUI view whose `rootView` is swapped on
  every update. The view is handed values rather than reading an observable, which is what keeps
  `PingUI` free of a second source of truth.
- **Anchor and margin are baked into the window frame**, so changing either closes the windows and makes
  new ones rather than re-laying-out the old.
- **Icons come from `IconCache`**, keyed by app name and fetched from `NSWorkspace` using the `appURL`
  the Dock reading carried. That is why `BadgeSnapshot` holds URLs and not `NSImage`s: the value type
  stays free of AppKit, and the one place that needs pixels asks for them.

### 7.3 Notch

A black strip hanging from the top edge — the notch, plus an extension either side holding one
indicator per badged app. On a MacBook it grows out of the real cutout; on a screen without one it
draws the notch too.

- **The geometry is public API.** `ScreenTopology.notch(of:standInWidth:)` reads it: the two
  `auxiliaryTop*Area` rects are both absent on a screen without a notch and both present on one with
  it, so their absence is the test and the cutout is the gap between them. There is no public answer
  for the cutout's corner radius, so `NotchStrip` carries the one every Mac that has one draws.
- **`NotchLayout` is the policy** and lives in `PingCore`: `(items, settings)` in, two sides, a tail
  and two widths out. Capacity per side is `floor((max-width − gap) / (item-size + gap))`; `split`
  halves the list in file order and widens both sides to the wider one's width, so an odd number of
  indicators does not tip the notch. The tail that does not fit takes turns in the last slot
  (`PRINCIPLES.md §3`) on `NotchRenderer`'s own clock, because a badge that does not change produces
  no render to ride on.
- **One window per display**, `.statusBar` — the floor, because the menu bar's *text* composites above
  anything lower. It is built at the strip's widest and never moved: a window that grew would be asking
  the window server to re-place it over the menu bar sixty times a second.
- **What moves is one layer.** `NotchStrip` animates the shape's `bounds` and `position` together, so
  the two extensions can differ while the cutout stays put. Its bounds run from −(left extension + half
  the cutout) to +(right extension + half the cutout), so `x = 0` is the cutout's middle whichever side
  is opening — which is what lets an indicator be positioned from the notch rather than from an edge
  that is moving; the indicators do not animate at all, and the opening strip reveals them.
  `masksToBounds` is load-bearing — an indicator that escaped the shape would be a coloured dot loose
  on the menu bar.
- **Absent is retracted, not gone.** `RenderState.notch == nil` closes the strip to the cutout it grew
  out of, or to nothing on a screen standing one in, so the effect leaves the way it arrived.
- **The extension covers, it does not reserve.** macOS reflows nothing around it: on the left it hides
  menu titles, on the right other apps' status items, and in full-screen it covers app content. Clicks
  still land, so what is hidden still works. `max-width`, `placement` and the fact that the extension
  is only out while something is badged are what hold it in proportion.

---

## 8. Config

**TOML**, at `~/.config/ping/ping.toml` (override: `PING_CONFIG`). Four pieces, split along one seam:
`PingConfig` is everything pure — what a file may say, what a key means, and how to change one value in
place — while `PingCore/ConfigLoader.swift` is the I/O.

### 8.1 The grammar — `TOML.swift`

TOML 1.0.0, scanned over Unicode **scalars** because that is the unit the spec's ABNF is written in and
every Swift property that looks like the right question (`isWhitespace`, `isNewline`) answers a
Unicode-wide one instead. Two things depart from what a plain TOML reader would hand back:

- **Paths are `TOMLKey`, never dotted `String`s.** Ping's middle segment is an app's Dock title —
  `[apps."Node.js"]` — and a dotted string cannot say whether that is one app or two tables. Segments
  are held apart everywhere and joined only to be shown.
- **An inline table remembers how it was written** (`TOMLInline`): the `{ … }` it occupies and each pair
  inside it, in file order. That is what lets a structural edit re-render the braces from their pairs
  instead of performing comma-and-whitespace surgery.

Whole TOML is read, not the part Ping uses: refusing a legal file at the grammar would say "not
supported" where the schema would have said "unknown key" and named the line. Every value carries the
line it was read on and the span of text it came from, which is what §8.3 is built out of.

### 8.2 The schema — `ConfigSchema.swift`, `ConfigReader.swift`, `ConfigTable.swift`

**The settings table is enumerable**, rather than existing only by being run. A `Setting` carries its
key, label, one sentence of help, a `Kind`, a section, and a codec that moves the value between the file
and a `Config` field. Three consumers come off the one list — the settings window lays itself out from
it, `ping-dot-app explain` prints it, and the document writer uses it to know that writing a default
means taking the line out.

- **One `Kind` per shape of control, never per setting** — `toggle`, `number(Bound, unit:)`, `choice`,
  `color`. A case serving a single key is the sign the table has stopped paying for itself.
- **The type is the vocabulary.** A `choice` reads its legal words off `CaseIterable`, so a case added
  to `Edge` or `ShelfAnchor` is accepted, named in the diagnostic and offered by a control with nothing
  in the table to update.
- **Reading is _taking_.** Each model pulls the keys it knows out of its `ConfigTable` and then asks
  what is left; whatever is left is a key the schema does not know, reported by line. There is exactly
  one list of known keys and it is `ConfigReader.swift`.
- **The reader is hand-written and the table does not drive it**, because the same five glow keys are
  read at four different depths (§4) and a flat table cannot say that. The two lists are pinned together
  by a test instead: every entry in the table is written into a document, read back through the real
  reader, and has to arrive as the field it claims.
- **`apps.*` is deliberately outside the table** — an open tree whose middle segment is a name the user
  invents and whose leaves are a cascade rather than values. It is read bespoke and edited by a panel
  written for it (§9).
- **Numbers are refused, never clamped**, with the bound in the message: a slider that cannot reach a
  value beats a file that does not mean what it says. A `camelCase` enum spelling is accepted with a
  diagnostic naming the spelling it moved to — leniency a file gets and a control does not need.

### 8.3 The document — `ConfigDocument.swift`

The config file as something you can edit. **Nothing here formats.** An edit splices over the stretch of
text one value occupies, or adds one line, and every other byte stays where the author left it —
including the spaces around a `=` and whether a number two lines up was typed `1` or `1.0`. A
`Config → TOML` serialiser would be a tenth of the code and would eat the comments, the ordering and the
blank lines that are the author's work.

- **Every field is a `let`, and an edit re-reads the whole document.** Spans move when text is spliced,
  so the alternative is bookkeeping that can fall out of step; re-reading cannot, and a config file is a
  page long. It also means an edit the schema refuses leaves the document exactly as it was.
- **`set(_ setting:to:)` is `set` _or_ `remove`**, because setting something to its default unsets it:
  an absent key already says what the default says, and writing it down pins it against ever changing.
  The fork lives on the `Setting`, which is the only thing that knows its own default.
- **`remove` takes the whole statement**, trailing comment included, and may name a whole table — which
  is how an app stops being subscribed to an effect. Between braces there is no line to take, so the
  `{ … }` is re-rendered without that pair; removing the last one leaves `{}`, because the app is still
  subscribed and just has nothing to say.
- **`expand` is the one edit that moves lines.** TOML will not let a header reopen an inline table, so
  writing `[apps.Messages.glow.dot]` under an app whose glow is a `{ … }` requires taking the braces
  apart first. The block goes directly after the run of lines it was written in, and the trailing
  comment travels to the header.
- **Where a new key goes is deterministic**, so writing the same change twice writes the same file: into
  the braces it belongs between, at the end of its table's run of key lines, or under a header appended
  for it. A top-level key goes above the first header, because TOML says it must.

### 8.4 Loading and watching — `PingCore/ConfigLoader.swift`

- **A missing file is not an error** — it loads as every default. A **broken** file changes nothing: the
  config already in hand stays on screen and the refusal is reported.
- **Two vnode sources: the file _and_ its directory.** Each half of "the file changed" is invisible to
  the other — an atomic save kills the file watch along with the inode it held, and an in-place rewrite
  never touches the directory entry. The file source is therefore re-armed _by path_ whenever its inode
  is renamed or unlinked, and a file that does not exist yet is fine, because the directory watch is
  what notices it appear.
- **A burst of events collapses into one read** 80 ms later, so one save is one reload however many
  events the editor produced writing it.
- **`changes()` yields only what reads differently**, which is what makes self-write suppression
  unnecessary rather than forgotten: a settings-window save comes back as a change to the config it
  already knows and is dropped. Failures are always reported, because a suppressed repeat would make a
  save that _didn't_ fix the problem look like one that did.
- **`textChanges()` yields every change to the text**, which is what an editing session needs and
  `changes()` deliberately will not give it: a comment somebody added is not a config change and is
  still their work.

---

## 9. The settings window

`Draft` (`PingUI/Draft.swift`) is one editing session: the document as the file was when it was opened,
the document as it now stands, and the complaint from the last edit that did not land. `isDirty`
compares the **text**, so a draft that set a key and set it back has changed nothing. **No I/O** — the
window owns the path, the atomic write and the watcher.

`Draft.Edit` has four cases, and the count is the point. A `Setting` is never absent — unsetting one
restores its default — but an app's subscription to an effect _is_ its presence in the file, and a
badge-kind override needs the braces taken apart before it can be written at all:

```
.setting(Setting, TOMLValue)   a key the table describes
.key(TOMLKey, TOMLValue)       one key of the surface the table cannot describe
.unset(TOMLKey)                out of the file entirely — not "back to its default"
.expand(TOMLKey)               an inline table rewritten as a header block
```

`SettingsModel` is the window's half: the path, the atomic write, and the watch.

- **Neither editor clobbers the other.** A change arriving on a clean draft is a silent re-read; on a
  dirty one it is held as `conflict`, both ways out are offered, and Save is refused until one is taken.
  The comparison is against the **baseline** — comparing against `rendered` would read the draft's own
  unsaved edits as the file having moved.
- **Unsaved edits survive being closed and reopened.** A window that was shut is not an edit session
  that was abandoned; discarding is a button.
- **Every tab but one is the schema walked** (`SettingsForm` builds one control per `Kind`), and that
  one is `AppsTab`, hand-written for the open tree. Its controls are three-state where the others are two: a
  row either says something or defers, and "defers" has to be reachable, or a per-app colour could be
  set and never unset.

---

## 10. The CLI

`ping-dot-app`, two verbs, both over `PingConfig` alone.

- **`validate [path]`** — exit 0, or exit 1 with `path:line: message` on stderr. Diagnostics go to
  stderr and do not fail the run. A missing file is valid: it means every default.
- **`explain [key]`** — what a key means, what it may be set to, and what it is when the file says
  nothing, printed off `Setting.all`. A whole table is as good an argument as one key, because
  `explain glow` is the question somebody actually has.

Everything it prints about itself is built from `argv[0]`, so a symlink named `ping` says `ping`.

---

## 11. Cross-cutting rules

- **Concurrency.** Everything that touches AppKit, AX or the engine is `@MainActor`; every value that
  crosses a boundary is `Sendable`. `ConfigTable` deliberately is not — it is a transient parse artifact
  sharing a diagnostic sink, and `Config` is the value that travels.
- **Platform floor: macOS 26.** Greenfield, so the floor is the newest and the current API surface is
  used everywhere — no `@available` checks, no legacy paths.
- **No `NSColor` below `PingUI`**, enforced by `ImportFenceTests` rather than intended.
- **The Dock's element is never cached across polls.** `DockReader.list()` re-derives it from
  `NSRunningApplication` every time, so a Dock relaunch costs one interval.
- **Every application item is read, not only the configured ones**, so a `BadgeSnapshot` is a fact about
  the Dock rather than about the config — which is what lets the settings picker offer titles the file
  has never mentioned.
- **Two environment overrides, both for testing.** `PING_CONFIG` moves the config file.
  `BADGES` is a JSON array of `{"appName": "Slack", "badge": "3", "at": 5}` applied on top of each
  reading, where `at` is seconds after launch and a null badge clears one — which is how the renderers
  get exercised without waiting for a real notification.
- **Logging** is `os.Logger` with subsystem `Ping` and one category per area (`polling`, `app`,
  `settings`, `accessibility`). A bundled app's stderr goes nowhere; `log stream --predicate
  'subsystem == "Ping"'` is where these land.
- **Onboarding** is a `WindowGroup` that shows itself only while `AXIsProcessTrusted()` is false, polls
  it once a second, and dismisses itself when the grant lands. It is a window rather than a menu item
  because a missing grant is indistinguishable from a quiet desktop (`PRINCIPLES.md §5`).

---

## 12. Directory map

```
Ping/
├── Package.swift · Makefile · README.md
├── .app/Contents/                       the bundle template: Info.plist (LSUIElement) + PkgInfo
├── .github/workflows/{ci,release}.yml   ci: lint + test + bundle on macos-26
├── .agents/{README,PRINCIPLES,IMPLEMENTATION,DOCS}.md + changes/<epoch>.md
├── Icon/Ping.icon/                      layered icon; `make icon` compiles it to Assets.car
└── Sources/
    ├── PingConfig/   TOML (grammar, spans, TOMLKey) · Config (the values + the cascade)
    │                 ConfigReader (the one list of known keys) · ConfigTable (typed takes)
    │                 ConfigSchema (the enumerable table) · ConfigDocument (the editable file)
    │                 Diagnostics · Color (RGBA, PingColor) · ConfigPath · ConfigExample
    ├── PingCore/     Dock/{DockReader, DockItem} — the AX traversal and the badge
    │                 BadgeMonitor (the poll) · BadgeSnapshot (one reading)
    │                 RuntimeState (snooze · acknowledgement · frontmost · preview)
    │                 EffectPreview · EffectResolver (THE decision) · RenderState
    │                 NotchLayout (where the indicators go, as arithmetic)
    │                 EffectEngine (the one observable) · ConfigLoader (+ ConfigWatcher)
    │                 ScreenTopology (which screens, and when that changes)
    ├── PingUI/       Glow/{GlowRenderer, GlowWindow, GlowView}
    │                 Shelf/{ShelfRenderer, ShelfWindow, ShelfView}
    │                 Notch/{NotchRenderer, NotchWindow, NotchStrip}
    │                 Rotator (the shared LRU) · IconCache
    │                 Settings/{SettingsWindow, SettingsModel, SettingsForm, AppsTab, DiagnosticsBar}
    │                 Draft (text ⇄ values) · MenuBar/MenuBarContent · Onboarding/AccessibilityView
    │                 Color (the one NSColor) · FontLoader · PingResources · Resources/
    ├── Ping/         PingApp (@main, the scenes) · AppDelegate (the four loops)
    └── PingCLI/      main.swift — validate · explain
```

One spelling recurs and is worth recognising: every framework-touching subsystem is a **pure model plus
a thin AppKit shell** (`Rotator`/`GlowView`, `NotchLayout`/`NotchStrip`, `Draft`/`SettingsModel`,
`EffectResolver`/the
renderers), so the interesting half is testable with no window server.

---

## 13. Testing

`make test`. The architecture exists to make testing cheap, so the pyramid is weighted at the bottom and
none of it needs a window server.

- **`PingConfigTests`** — the grammar (`TOMLParserTests`), the schema and every diagnostic by line
  number (`ConfigReaderTests`), the cascade's whole truth table (`ResolutionTests`), the editable
  document over a corpus of round-trips and structural edits (`ConfigDocumentTests`), the table against
  the reader (`ConfigSchemaTests`), the shipped example parsing to what it looks like it says
  (`ConfigExampleTests`), and the import fence (`ImportFenceTests`).
- **`PingCoreTests`** — `AcknowledgementTests` for the count/dot rules that came across from the
  pre-rewrite poller unchanged, subtle, and previously untested; `EffectResolverTests` for what reaches
  the screen: only badged apps, an unmentioned app rendering nothing, the shelf and the notch being
  absent rather than empty, snooze, acknowledgement, focus suppression, `bundle-id` matching, and a
  preview standing in for the live snapshot while ignoring every suppression; and `NotchLayoutTests`
  for the strip's arithmetic — capacity, the three placements, the split's equal-width rule, and a tail
  that overflows rather than being dropped.
- **`PingUITests`** — `DraftTests` for an edit as text, unset-on-default and a refusal that does not
  land; `SettingsModelTests` for the two-editor rules — a clean draft re-reading silently, a dirty one
  reporting a conflict, Save held until it is resolved, and a save not reading as a reload; and
  `NotchStripTests` for the arithmetic reaching the screen — in each placement, the innermost indicator
  one gap from the cutout in the window's own coordinates, and none of them outside the shape that
  masks them.

**What the suite does not cover**, and therefore needs the app actually running: anything about the
window server (which space a window is on, whether an overlay survives a full-screen app), anything
visual, and the AX traversal itself, which needs a real Dock and a real grant. Per `CLAUDE.md`, running
the binary and making a badge appear is never an interruption — `BADGES` exists for exactly that.

---

## 14. Build & release

`make` (the default: build, bundle, sign) · `make test` · `make cli` · `make install` (the bundle
into `/Applications`, or `INSTALL_DIR`) · `make dist` · `make lint`.

- **The app is one process with two executables in it.** `Contents/MacOS/Ping` is `CFBundleExecutable`;
  `ping-dot-app` rides along beside it so there is exactly one copy of the config reader on the machine
  and no chance of a CLI and an app from different builds disagreeing about what the file means. Nothing
  puts it on `$PATH` — that is a cask's `binary` stanza, or a symlink you make.
- **`LSUIElement`** — Ping is a menu bar agent with no Dock tile of its own. Launch-at-login is
  `SMAppService.mainApp`, and the file wins on load: the config is read and the service is synced to it.
- **TCC records a grant against the code signature of what runs.** Ad-hoc signing identifies the app by
  cdhash, which changes with every build, so macOS re-asks for Accessibility on every rebuild until a
  Developer ID signature (`CODESIGN_IDENTITY`) replaces it. The nested CLI is signed **before** the app,
  because signing a bundle seals its `Contents`.
- **The git tag is the only version authority.** No file in the tree carries a number; `make app` asks
  `git describe` and stamps the answer into the bundle's _copy_ of `Info.plist`.
- **The icon needs Xcode, not the Command Line Tools** — `actool` lives in the former. A machine without
  it builds a bundle with no icon and says so, rather than failing. The bell is black, for 17:1 against
  the green in the appearance most people see, and that costs the other two: macOS builds the tinted and
  clear variants from the layer's luminance, so a dark glyph comes back a faint emboss. It also means
  `icon.json` has to state its `dark` fill — left out, the system darkens the ground under a black bell.
- Archives are `ditto -c -k --keepParent`, never `zip`, which mangles symlinks, xattrs and the
  signature. Builds are arm64 only; the platform floor is macOS 26.
