//
//  EffectPreview.swift
//  PingCore
//
//  What an open settings window is asking to *see*. `EffectEngine.previewConfig` answers "drawn
//  from which config"; this answers "drawn for whom, and which effect".
//
//  A preview is never a second code path. It is the ordinary resolution run over a synthetic
//  reading of the Dock, which is why a preview cannot drift from what a real badge would do.
//

import PingConfig

/// The effects a preview is about.
///
/// Scoped, because the window is: the Glow tab has no business putting a shelf on screen, and a
/// shelf that appears while a glow is being edited reads as a bug rather than as a preview.
public struct PreviewEffects: OptionSet, Equatable, Sendable {
  public let rawValue: Int

  public init(rawValue: Int) {
    self.rawValue = rawValue
  }

  public static let glow = PreviewEffects(rawValue: 1 << 0)
  public static let shelf = PreviewEffects(rawValue: 1 << 1)
  public static let all: PreviewEffects = [.glow, .shelf]
}

public struct EffectPreview: Equatable, Sendable {
  /// Stands in for the Dock: which apps are badged, and with what.
  public var snapshot: BadgeSnapshot
  /// What may be drawn. Anything outside this stays off screen, whatever the config says.
  public var effects: PreviewEffects
  /// Stand-in apps, drawn alongside the file's own.
  ///
  /// A config that subscribes nobody to the effect being edited would otherwise preview an empty
  /// screen, which is the one thing a preview must not do — the shelf settings are worth looking
  /// at before any app is on the shelf. Anything the file already says about an app wins over a
  /// stand-in for it.
  public var samples: [AppConfig]

  public init(
    snapshot: BadgeSnapshot,
    effects: PreviewEffects = .all,
    samples: [AppConfig] = []
  ) {
    self.snapshot = snapshot
    self.effects = effects
    self.samples = samples
  }
}
