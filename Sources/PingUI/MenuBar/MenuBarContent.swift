//
//  MenuBarContent.swift
//  PingUI
//
//  The menu: what Ping made of the file, the two things you reach for without opening anything
//  (acknowledge, snooze), and the two ways in — the settings window, and the file itself.
//

import PingConfig
import PingCore
import SwiftUI

public struct MenuBarContent: View {
  private let engine: EffectEngine

  public init(engine: EffectEngine) {
    self.engine = engine
  }

  public var body: some View {
    Text("ping").font(.custom("Chango", size: 13))
    Divider()
    DiagnosticsContent(engine: engine)
    AcknowledgeContent(engine: engine)
    Divider()
    SnoozeContent(engine: engine)
    Divider()
    SettingsLink {
      Text("Settings…")
    }
    .keyboardShortcut(",", modifiers: .command)
    Button("Edit ping.toml") {
      let url = ConfigPath.url
      if !FileManager.default.fileExists(atPath: url.path) {
        try? FileManager.default.createDirectory(
          at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? ConfigExample.text.write(to: url, atomically: true, encoding: .utf8)
      }
      NSWorkspace.shared.open(url)
    }
    Button("Quit") {
      NSApplication.shared.terminate(nil)
    }
    .keyboardShortcut("q", modifiers: .command)
  }
}

/// A broken file leaves the last good config on screen, so the only way to know is here.
struct DiagnosticsContent: View {
  let engine: EffectEngine

  var body: some View {
    if let failure = engine.loadFailure {
      Text("⚠ \(failure)")
      Divider()
    } else if !engine.diagnostics.isEmpty {
      ForEach(engine.diagnostics.indices, id: \.self) { index in
        Text("⚠ \(engine.diagnostics[index].description)")
      }
      Divider()
    }
  }
}

struct AcknowledgeContent: View {
  let engine: EffectEngine

  var body: some View {
    Button("Acknowledge") {
      engine.acknowledge()
    }
    .disabled(!engine.hasBadges)
    if engine.runtime.hasAcknowledgedApps {
      let names = engine.runtime.acknowledged.keys.sorted().joined(separator: ", ")
      Text("Suppressed: \(names)")
    }
  }
}

struct SnoozeContent: View {
  let engine: EffectEngine
  @State private var now = Date()

  private let durations: [Int] = [1, 5, 10, 15, 20, 30, 45, 60]

  var body: some View {
    if engine.isSnoozed, let snoozedUntil = engine.runtime.snoozedUntil {
      let remaining = max(0, Int(snoozedUntil.timeIntervalSince(now)))
      Button(
        "End snooze early (\(String(format: "%02d:%02d", remaining / 60, remaining % 60)))"
      ) {
        engine.endSnooze()
      }
      // A plain tick rather than a Combine timer: `Timer.publish` leaks `Publishers.Autoconnect`
      // into this type's signature, which is a warning about a property nothing outside reads.
      .task {
        while !Task.isCancelled {
          now = Date()
          try? await Task.sleep(for: .seconds(1))
        }
      }
    } else {
      Menu("Snooze") {
        ForEach(durations, id: \.self) { minutes in
          Button("\(minutes) minute\(minutes == 1 ? "" : "s")") {
            engine.snooze(minutes: minutes)
          }
        }
      }
    }
  }
}
