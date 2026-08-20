//
//  EffectEngine.swift
//  PingCore
//
//  The one observable object in the app. Everything it holds is a value; everything it
//  answers is derived. `renderState` is what the renderers watch, which is what collapses
//  the old twelve `withObservationTracking` re-arm loops into one.
//

import Foundation
import PingConfig

@Observable
@MainActor
public final class EffectEngine {

  public var config: Config
  public var snapshot = BadgeSnapshot()
  public var runtime = RuntimeState()

  /// What an open settings window is editing, drawn instead of the saved config.
  ///
  /// The draft's own reading of the file it *would* write, so a colour chosen in the window is on
  /// screen before Save — and Save then only decides whether it persists. Cleared when the window
  /// closes, which puts the saved file back without anything having to remember what it said.
  public var previewConfig: Config?

  /// Anything the config file said that is worth repeating back — spellings that moved,
  /// or the refusal that kept the last good config on screen.
  public var diagnostics: [ConfigDiagnostic] = []
  public var loadFailure: String?

  private var snoozeTask: Task<Void, Never>?

  public init(config: Config = Config()) {
    self.config = config
  }

  /// The config everything on screen is drawn from — the draft's while a settings window is open.
  public var effectiveConfig: Config { previewConfig ?? config }

  public var renderState: RenderState {
    EffectResolver.renderState(
      config: effectiveConfig, snapshot: snapshot, runtime: runtime, now: Date())
  }

  // MARK: - Input

  /// Fold in a fresh reading of the Dock, ageing the acknowledgements along with it.
  public func apply(_ snapshot: BadgeSnapshot) {
    runtime.reconcile(with: snapshot)
    self.snapshot = snapshot
  }

  /// A broken file changes nothing: the config already in hand stays on screen and the
  /// refusal is reported.
  public func apply(_ result: Result<ParsedConfig, Error>) {
    switch result {
    case .success(let parsed):
      config = parsed.config
      diagnostics = parsed.diagnostics
      loadFailure = nil
    case .failure(let error):
      loadFailure = "\(error)"
    }
  }

  // MARK: - Menu bar actions

  public var isSnoozed: Bool { runtime.isSnoozed(at: Date()) }

  public func snooze(minutes: Int) {
    let until = Date().addingTimeInterval(Double(minutes) * 60)
    runtime.snoozedUntil = until
    snoozeTask?.cancel()
    // Nothing else would notice the moment a snooze runs out, so wake for it.
    snoozeTask = Task { @MainActor [weak self] in
      try? await Task.sleep(for: .seconds(until.timeIntervalSinceNow))
      guard !Task.isCancelled else { return }
      self?.endSnooze()
    }
  }

  public func endSnooze() {
    snoozeTask?.cancel()
    snoozeTask = nil
    runtime.snoozedUntil = nil
  }

  public func acknowledge() {
    runtime.acknowledge(snapshot)
  }

  public var hasBadges: Bool { !snapshot.badges.isEmpty }
}
