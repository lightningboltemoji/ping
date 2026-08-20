import Foundation
import PingConfig
import PingCore
import Testing

@testable import PingUI

/// The done-criterion, as a test: *edit in vim and in the GUI, neither clobbers the other*.
///
/// The vnode watch itself is `PingCore`'s; what is decided here is what to *do* when it fires —
/// rebase a clean draft silently, hold a dirty one and say so, and treat a save coming back as the
/// nothing it is.
@Suite("Settings model")
@MainActor
struct SettingsModelTests {

  private let handWritten = """
    # my ping config — do not let a GUI eat this
    poll-interval-ms = 250

    [glow]
    color = "green"   # everything starts here

    [apps.Slack]
    glow  = { color = "#611f69" }
    shelf = {}

    """

  /// A scratch file that goes away with the test.
  private func scratch(_ contents: String) throws -> URL {
    let url = URL.temporaryDirectory.appending(
      path: "ping-settings-\(UUID().uuidString)/ping.toml")
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try contents.write(to: url, atomically: true, encoding: .utf8)
    return url
  }

  private func model(_ contents: String) throws -> (SettingsModel, EffectEngine, URL) {
    let url = try scratch(contents)
    let engine = EffectEngine()
    let model = SettingsModel(engine: engine, url: url)
    model.open()
    return (model, engine, url)
  }

  private func setting(_ key: TOMLKey) throws -> Setting {
    try #require(Setting.setting(for: key))
  }

  @Test("opening reads the file and shows it")
  func opens() throws {
    let (model, _, _) = try model(handWritten)
    #expect(model.openFailure == nil)
    #expect(!model.isDirty)
    #expect(model.config.general.pollIntervalMS == 250)
    #expect(model.config.apps.map(\.name) == ["Slack"])
  }

  @Test("a file that does not parse leaves nothing to edit, and says why")
  func brokenFile() throws {
    let (model, _, _) = try model("[glow]\ncolour = \"green\"\n")
    #expect(model.draft == nil)
    #expect(model.openFailure?.contains("unknown key 'glow.colour'") == true)
  }

  @Test("an edit shows before it is saved, and Save is what writes it")
  func editsPreviewThenSave() throws {
    let (model, engine, url) = try model(handWritten)
    model.set(try setting(["glow", "color"]), to: .string("blue"))

    // On screen at once...
    #expect(engine.previewConfig?.glow.defaults.color == .named(.blue))
    #expect(engine.effectiveConfig.glow.defaults.color == .named(.blue))
    // ...but not in the file.
    #expect(try String(contentsOf: url, encoding: .utf8) == handWritten)
    #expect(model.isDirty)

    model.save()
    #expect(!model.isDirty)
    let written = try String(contentsOf: url, encoding: .utf8)
    #expect(written.contains("color = \"blue\"   # everything starts here"))
    // The rest of somebody's file, untouched.
    #expect(written.contains("# my ping config — do not let a GUI eat this"))
    #expect(written.contains(##"glow  = { color = "#611f69" }"##))
    #expect(written.split(separator: "\n").count == handWritten.split(separator: "\n").count)
  }

  @Test("closing puts the saved config back on screen")
  func closeClearsPreview() throws {
    let (model, engine, _) = try model(handWritten)
    model.set(try setting(["glow", "color"]), to: .string("blue"))
    #expect(engine.previewConfig != nil)
    model.close()
    #expect(engine.previewConfig == nil)
    #expect(engine.runtime.preview == nil)
  }

  @Test("the file changing under a clean draft is a silent re-read")
  func rebasesWhenClean() throws {
    let (model, engine, _) = try model(handWritten)
    let theirs = handWritten.replacingOccurrences(of: "\"green\"", with: "\"purple\"")
    model.fileChanged(theirs)

    #expect(model.conflict == nil)
    #expect(!model.isDirty)
    #expect(model.config.glow.defaults.color == .named(.purple))
    #expect(engine.previewConfig?.glow.defaults.color == .named(.purple))
  }

  @Test("the file changing under a dirty draft is held, not applied")
  func conflictWhenDirty() throws {
    let (model, _, _) = try model(handWritten)
    model.set(try setting(["shelf", "icon-size"]), to: .number(48))
    #expect(model.isDirty)

    model.fileChanged(handWritten.replacingOccurrences(of: "\"green\"", with: "\"purple\""))
    #expect(model.conflict != nil)
    // Neither half is lost: the edit is still here, and Save waits.
    #expect(model.config.shelf.iconSize == 48)
    #expect(!model.canSave)
  }

  @Test("a conflict resolves either way, and Save works again after")
  func resolvesConflict() throws {
    let theirs = handWritten.replacingOccurrences(of: "\"green\"", with: "\"purple\"")

    // Their way: take the file, lose the edit.
    let (mine, _, url) = try model(handWritten)
    mine.set(try setting(["shelf", "icon-size"]), to: .number(48))
    try theirs.write(to: url, atomically: true, encoding: .utf8)
    mine.fileChanged(theirs)
    mine.reloadFromDisk()
    #expect(mine.conflict == nil)
    #expect(!mine.isDirty)
    #expect(mine.config.glow.defaults.color == .named(.purple))
    #expect(mine.config.shelf.iconSize == ShelfSettings().iconSize)

    // My way: keep the edit, overwrite the file.
    let (ours, _, ourURL) = try model(handWritten)
    ours.set(try setting(["shelf", "icon-size"]), to: .number(48))
    try theirs.write(to: ourURL, atomically: true, encoding: .utf8)
    ours.fileChanged(theirs)
    ours.overwrite()
    #expect(ours.conflict == nil)
    #expect(!ours.isDirty)
    #expect(try String(contentsOf: ourURL, encoding: .utf8).contains("icon-size = 48"))
  }

  @Test("closing and reopening keeps unsaved edits")
  func reopenKeepsEdits() throws {
    let (model, _, _) = try model(handWritten)
    model.set(try setting(["shelf", "icon-size"]), to: .number(48))
    model.close()
    model.open()
    #expect(model.isDirty)
    #expect(model.config.shelf.iconSize == 48)
    #expect(model.conflict == nil)
  }

  @Test("reopening onto a file that moved underneath says so rather than choosing")
  func reopenOntoChangedFile() throws {
    let (model, _, url) = try model(handWritten)
    model.set(try setting(["shelf", "icon-size"]), to: .number(48))
    model.close()
    try handWritten.replacingOccurrences(of: "\"green\"", with: "\"purple\"")
      .write(to: url, atomically: true, encoding: .utf8)
    model.open()
    #expect(model.conflict != nil)
    #expect(model.config.shelf.iconSize == 48)
    #expect(!model.canSave)
  }

  @Test("a save coming back through the watcher is the nothing it is")
  func ownSaveIsNotAChange() throws {
    let (model, _, url) = try model(handWritten)
    model.set(try setting(["glow", "color"]), to: .string("blue"))
    model.save()
    model.fileChanged(try String(contentsOf: url, encoding: .utf8))
    #expect(model.conflict == nil)
    #expect(!model.isDirty)
  }

  @Test("the app in hand is previewed, and a hover previews ahead of the selection")
  func appPreview() throws {
    let (model, engine, _) = try model(handWritten)
    model.section = .apps

    model.selectedApp = "Slack"
    #expect(engine.runtime.preview?.snapshot.badges["Slack"]?.raw == "1")
    #expect(engine.runtime.preview?.effects == .all)

    model.apply(.key(["apps", "Mail", "glow"], .emptyTable()))
    model.hoveredApp = "Mail"
    #expect(engine.runtime.preview?.snapshot.badges.keys.sorted() == ["Mail"])
    model.hoveredApp = nil
    #expect(engine.runtime.preview?.snapshot.badges.keys.sorted() == ["Slack"])
  }

  @Test("the badge kind under the pointer is the badge the preview shows")
  func previewBadgeKind() throws {
    let (model, engine, _) = try model(handWritten)
    model.section = .apps
    model.selectedApp = "Slack"

    model.previewBadge = .dot
    #expect(engine.runtime.preview?.snapshot.badges["Slack"]?.kind == .dot)
    model.previewBadge = .count
    #expect(engine.runtime.preview?.snapshot.badges["Slack"]?.kind == .count)
  }

  @Test("an effect tab previews that effect, on the apps subscribed to it")
  func effectTabPreview() throws {
    let (model, engine, _) = try model(handWritten)

    model.section = .glow
    #expect(engine.runtime.preview?.effects == .glow)
    #expect(engine.runtime.preview?.snapshot.badges.keys.sorted() == ["Slack"])
    #expect(engine.runtime.preview?.samples.isEmpty == true)

    model.section = .shelf
    #expect(engine.runtime.preview?.effects == .shelf)
    #expect(engine.runtime.preview?.snapshot.badges.keys.sorted() == ["Slack"])

    // Nothing to look at on the General tab, so nothing is put on screen.
    model.section = .general
    #expect(engine.runtime.preview == nil)
  }

  @Test("an effect nobody is subscribed to previews on stand-ins")
  func effectTabPreviewFallsBackToSamples() throws {
    let (model, engine, _) = try model("[apps.Slack]\nglow = {}\n")
    engine.snapshot = BadgeSnapshot(dockTitles: ["Finder", "Mail", "Notes", "Music"])

    model.section = .shelf
    let preview = try #require(engine.runtime.preview)
    #expect(preview.effects == .shelf)
    // Three stand-ins, taken from the Dock and skipping what the file already lists.
    #expect(preview.samples.map(\.name) == ["Finder", "Mail", "Notes"])
    #expect(preview.samples.allSatisfy { $0.shelf != nil && $0.glow == nil })
    #expect(preview.snapshot.badges.keys.sorted() == ["Finder", "Mail", "Notes"])
  }

  @Test("closing takes the preview off screen and reopening puts it back")
  func previewFollowsTheWindow() throws {
    let (model, engine, _) = try model(handWritten)
    model.section = .glow
    #expect(engine.runtime.preview != nil)

    model.close()
    #expect(engine.runtime.preview == nil)
    // A closed window has nobody looking, so nothing it says moves the screen.
    model.section = .shelf
    #expect(engine.runtime.preview == nil)

    model.open()
    #expect(engine.runtime.preview?.effects == .shelf)
  }

  @Test("subscribing and unsubscribing an app is presence, not a value")
  func subscriptions() throws {
    let (model, _, _) = try model(handWritten)
    model.apply(.key(["apps", "Mail", "glow"], .emptyTable()))
    #expect(model.config.apps.map(\.name).sorted() == ["Mail", "Slack"])
    #expect(model.config.app(named: "Mail")?.glow != nil)

    model.apply(.unset(["apps", "Slack", "shelf"]))
    #expect(model.config.app(named: "Slack")?.shelf == nil)
    #expect(model.config.app(named: "Slack")?.glow != nil)
    #expect(model.refusal == nil)
  }
}
