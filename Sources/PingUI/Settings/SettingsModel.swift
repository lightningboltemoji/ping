//
//  SettingsModel.swift
//  PingUI
//
//  The window's half of the edit session: `Draft` is text ⇄ values and holds no path, so this is
//  the path, the atomic write, and the watch that keeps the two editors out of each other's way.
//
//  **Neither editor clobbers the other.** The file is watched while the window is open. A change
//  arriving on a draft with nothing unsaved in it is a silent re-read; a change arriving on a
//  dirty one is *reported* rather than applied, because throwing away typing is worse than either
//  version of the file. Save then refuses until that is resolved one way or the other.
//
//  **Edits show before they are saved.** Every edit pushes the draft's reading of the file it
//  would write into `EffectEngine.previewConfig`, so a colour chosen here is on screen at once and
//  Save only decides whether it persists. Closing the window clears it, which puts the saved file
//  back with nothing having to remember what it said.
//
//  **The preview follows the window, not the pointer.** A config is only half of what is on
//  screen; the other half is whether anything is badged, and while the settings are open the
//  answer has to be "yes, whatever you are looking at". So the tab in front decides: the Glow tab
//  badges the apps that glow, the Shelf tab badges the apps on the shelf, and the Apps tab badges
//  the app in hand. That is what makes a slider move something rather than describe something —
//  a hover-only preview died the moment the pointer reached the control it was previewing.
//

import Foundation
import PingConfig
import PingCore
import SwiftUI
import os

private let logger = Logger(subsystem: "Ping", category: "settings")

@Observable
@MainActor
public final class SettingsModel {

  /// Why the window has nothing to edit: the file does not parse, and splicing text whose meaning
  /// is unknown is the one thing a GUI must not do. The window says so and offers the editor.
  public private(set) var openFailure: String?

  /// The file changed under a draft that had unsaved edits in it. Held rather than applied — the
  /// window offers the two ways out, and Save is refused until one is taken.
  public private(set) var conflict: String?

  public private(set) var draft: Draft?

  private let engine: EffectEngine
  private let loader: ConfigLoader
  private var watch: Task<Void, Never>?

  /// Whether a window is up. Nothing pushes a preview without one — a preview is a thing being
  /// looked at, and there is nobody looking after the window goes.
  private var isOpen = false

  public init(engine: EffectEngine, url: URL = ConfigPath.url) {
    self.engine = engine
    self.loader = ConfigLoader(url: url)
  }

  public var url: URL { loader.url }

  public var isDirty: Bool { draft?.isDirty ?? false }

  /// The complaint the last edit produced, if it did not land.
  public var refusal: String? { draft?.refusal }

  public var diagnostics: [ConfigDiagnostic] { draft?.diagnostics ?? [] }

  /// The config the window is showing — the draft's while it has one, so every control reads the
  /// file that would be saved rather than the one that was.
  public var config: Config { draft?.config ?? engine.config }

  // MARK: - Opening and closing

  /// Read the file and start watching it. Called when the window appears.
  ///
  /// **Unsaved edits survive being closed and reopened.** A window that is shut is not an edit
  /// session that was abandoned — nothing asked for the typing to go — so coming back reconciles
  /// with whatever the file did in the meantime by the same rules the watcher uses, rather than
  /// starting again. Discarding is a button.
  public func open() {
    isOpen = true
    reread(replacingEdits: false)
    // Reopening on an unchanged file is a no-op re-read, so the preview is put back here rather
    // than there: the window is up again, and the window is what puts an effect on screen.
    pushPreview()
    guard watch == nil else { return }
    watch = Task { [weak self] in
      guard let stream = self?.loader.textChanges() else { return }
      for await text in stream {
        self?.fileChanged(text ?? "")
      }
    }
  }

  private func reread(replacingEdits: Bool) {
    let text = (try? String(contentsOf: loader.url, encoding: .utf8)) ?? ""
    if draft != nil, !replacingEdits {
      fileChanged(text)
      return
    }
    do {
      draft = try Draft(text)
      openFailure = nil
      conflict = nil
      pushPreview()
    } catch {
      draft = nil
      openFailure = "\(error)"
    }
  }

  /// Stop watching and put the saved config back on screen. An unsaved draft is kept, so closing
  /// and reopening the window does not silently discard typing.
  public func close() {
    isOpen = false
    watch?.cancel()
    watch = nil
    engine.previewConfig = nil
    engine.runtime.preview = nil
  }

  /// The file moved under us. Internal rather than private so a test can hand it a change without
  /// waiting on a real filesystem event — the vnode plumbing underneath is `PingCore`'s.
  func fileChanged(_ text: String) {
    guard var draft else {
      // The window is sitting on a file it couldn't read. If it parses now, take it.
      reread(replacingEdits: true)
      return
    }
    // Against the *baseline* — what the file was when this draft last agreed with it. Comparing
    // against `rendered` would read the draft's own unsaved edits as the file having moved, and a
    // save coming back is covered too: saving makes the baseline the text that was written.
    guard text != draft.baseline.rendered else { return }
    guard !draft.isDirty else {
      conflict = "\(loader.url.lastPathComponent) changed on disk while you were editing."
      return
    }
    do {
      try draft.reload(text)
      self.draft = draft
      conflict = nil
      pushPreview()
    } catch {
      // A file that stopped parsing leaves the draft alone: the window keeps showing the last
      // thing it could read, and the app keeps rendering the last thing it could load.
      openFailure = "\(error)"
    }
  }

  // MARK: - Editing

  public func apply(_ edit: Draft.Edit) {
    guard var draft else { return }
    draft.apply(edit)
    self.draft = draft
    pushPreview()
  }

  public func set(_ setting: Setting, to value: TOMLValue) {
    apply(.setting(setting, value))
  }

  public func value(of setting: Setting) -> TOMLValue {
    draft?.value(of: setting) ?? setting.value(in: engine.config)
  }

  // MARK: - What the window is showing
  //
  // Four bound values, and everything about the preview falls out of them. Each pushes, so the
  // preview is rebuilt on every edit as well as on every move: subscribing an app to the shelf
  // puts it on the shelf as the switch moves, because the switch wrote the config the preview
  // resolves against.

  public var section: Setting.Section = .general {
    didSet { pushPreview() }
  }

  /// The app whose panel is open.
  public var selectedApp: String? {
    didSet { pushPreview() }
  }

  /// The row under the pointer, previewed ahead of the selection so a list can be skimmed.
  public var hoveredApp: String? {
    didSet { pushPreview() }
  }

  /// Which badge kind the app panel is previewing. The `count` and `dot` sections set it as the
  /// pointer crosses them, because an override for a badge kind the Dock is not currently showing
  /// is otherwise impossible to look at.
  public var previewBadge: BadgeKind = .count {
    didSet { pushPreview() }
  }

  /// Push both halves of what is on screen: the config being edited, and a reading of the Dock
  /// that makes the part being edited visible.
  private func pushPreview() {
    guard isOpen else { return }
    engine.previewConfig = draft?.config
    engine.runtime.preview = preview(in: config)
  }

  /// The synthetic Dock the preview resolves against, or `nil` when there is nothing to look at.
  private func preview(in config: Config) -> EffectPreview? {
    switch section {
    case .general:
      // Poll interval, monitors, launch-at-login: nothing here draws.
      return nil

    case .apps:
      guard let name = hoveredApp ?? selectedApp else { return nil }
      return EffectPreview(snapshot: snapshot(badging: [name]), effects: .all)

    case .glow, .shelf:
      let effects: PreviewEffects = section == .glow ? .glow : .shelf
      let subscribed = config.apps.filter { subscribes($0, to: effects, in: config) }
      guard subscribed.isEmpty else {
        return EffectPreview(
          snapshot: snapshot(badging: subscribed.map(\.name)), effects: effects)
      }
      // Nobody is signed up for the effect being edited, so it is previewed on stand-ins —
      // the alternative is settings that do nothing until an app is subscribed elsewhere.
      let samples = samples(for: effects, in: config)
      return EffectPreview(
        snapshot: snapshot(badging: samples.map(\.name)), effects: effects, samples: samples)
    }
  }

  private func subscribes(_ app: AppConfig, to effects: PreviewEffects, in config: Config) -> Bool {
    if effects.contains(.glow), config.resolvedGlow(for: app, badge: previewBadge) != nil {
      return true
    }
    if effects.contains(.shelf), config.shelfShows(app) {
      return true
    }
    return false
  }

  /// A reading of the Dock that says these apps are badged.
  ///
  /// A real badge is kept where there is one, so previewing an app that is actually notifying
  /// shows the notification rather than a stand-in for it.
  private func snapshot(badging names: [String]) -> BadgeSnapshot {
    var badges: [String: Badge] = [:]
    for name in names {
      badges[name] = badge(for: name)
    }
    return BadgeSnapshot(
      badges: badges,
      dockTitles: engine.snapshot.dockTitles,
      appURLs: engine.snapshot.appURLs)
  }

  private func badge(for name: String) -> Badge {
    if previewBadge == .count, let live = engine.snapshot.badges[name], live.kind == .count {
      return live
    }
    return Badge(raw: previewBadge == .count ? "1" : "")
  }

  /// Stand-in apps for a config that subscribes nobody to the effect being edited.
  ///
  /// Taken from the Dock where it can be, so the shelf previews real icons and real names rather
  /// than a fiction. The shelf is a row and wants a few; a glow is one wash of colour per edge and
  /// wants one.
  private func samples(for effects: PreviewEffects, in config: Config) -> [AppConfig] {
    let wanted = effects.contains(.shelf) ? 3 : 1
    let listed = Set(config.apps.map(\.name))
    let names = engine.snapshot.dockTitles.filter { !listed.contains($0) }.prefix(wanted)
    // An unreadable Dock (no Accessibility grant yet) still gets something to look at.
    let stand = names.isEmpty ? ["Preview"] : Array(names)
    return stand.map { name in
      AppConfig(
        name: name,
        glow: effects.contains(.glow) ? AppGlow() : nil,
        shelf: effects.contains(.shelf) ? AppShelf() : nil)
    }
  }

  // MARK: - Saving

  public var canSave: Bool { isDirty && conflict == nil }

  /// Write the draft, atomically. The watcher sees it come back and finds nothing changed, so a
  /// save is not a reload.
  public func save() {
    guard var draft, conflict == nil else { return }
    do {
      try FileManager.default.createDirectory(
        at: loader.url.deletingLastPathComponent(), withIntermediateDirectories: true)
      try draft.rendered.write(to: loader.url, atomically: true, encoding: .utf8)
      draft.saved()
      self.draft = draft
    } catch {
      logger.error("Could not write \(self.loader.url.path): \(error)")
      openFailure = "Could not save: \(error.localizedDescription)"
    }
  }

  public func discard() {
    guard var draft else { return }
    draft.discard()
    self.draft = draft
    conflict = nil
    pushPreview()
  }

  /// Take what is on disk and lose the unsaved edits — the conflict resolved the file's way. The
  /// one thing here that throws typing away, which is why it is a button and not a lifecycle hook.
  public func reloadFromDisk() {
    conflict = nil
    reread(replacingEdits: true)
  }

  /// Keep the unsaved edits and overwrite what is on disk — the conflict resolved the window's way.
  public func overwrite() {
    conflict = nil
    save()
  }
}
