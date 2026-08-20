//
//  SettingsWindow.swift
//  PingUI
//
//  The settings window: four tabs, a diagnostics bar, and Save.
//
//  **The file is still the settings.** This window is a reader and writer for `ping.toml`, not a
//  second source of truth — every control writes one key through `Draft`, and "Edit ping.toml" is
//  right there because the file is the thing being edited either way.
//
//  **Save is explicit, but the effect is not.** Every edit shows on screen immediately, because the
//  engine draws from the draft while this is open (`SettingsModel.pushPreview`); Save only decides
//  whether it persists. That is what makes Discard mean something, and it is what lets a window
//  that is refusing an edit still show the file the user has.
//
//  The tab in front is the preview's subject, so it is bound to the model rather than held here:
//  opening Glow pops a glow and opening Shelf pops a shelf, for as long as that tab is up.
//

import PingConfig
import PingCore
import SwiftUI

public struct SettingsView: View {
  @Bindable private var model: SettingsModel
  private let engine: EffectEngine

  public init(model: SettingsModel, engine: EffectEngine) {
    self.model = model
    self.engine = engine
  }

  public var body: some View {
    VStack(spacing: 0) {
      TabView(selection: $model.section) {
        ForEach(Setting.Section.allCases, id: \.self) { section in
          tab(section)
            .tabItem { Label(section.title, systemImage: icon(for: section)) }
            .tag(section)
        }
      }
      Divider()
      footer
    }
    .frame(minWidth: 620, minHeight: 460)
    .environment(model)
    .onAppear {
      model.open()
      // Ping lives in the menu bar, so nothing has brought it forward: without this the window
      // opens behind whatever the user was looking at when they asked for it.
      NSApp.activate()
    }
    .onDisappear { model.close() }
  }

  @ViewBuilder
  private func tab(_ section: Setting.Section) -> some View {
    if model.draft == nil {
      // Nothing to edit: the file does not parse, and splicing text whose meaning is unknown is
      // the one thing this must not do. Say so, and offer the editor.
      ContentUnavailableView {
        Label("Ping can't read your config", systemImage: "doc.badge.gearshape")
      } description: {
        Text(model.openFailure ?? "").font(.callout.monospaced())
      } actions: {
        Button("Open ping.toml") { NSWorkspace.shared.open(model.url) }
        Button("Try again") { model.open() }
      }
    } else if section == .apps {
      AppsTab(model: model, engine: engine)
    } else {
      SettingsForm(section: section, model: model)
    }
  }

  private var footer: some View {
    VStack(alignment: .leading, spacing: 8) {
      DiagnosticsBar(model: model)
      HStack(spacing: 8) {
        Button("Edit ping.toml") { NSWorkspace.shared.open(model.url) }
          .help(model.url.path)
        Spacer()
        if model.isDirty {
          Text("Unsaved").foregroundStyle(.secondary).font(.callout)
        }
        Button("Discard") { model.discard() }
          .disabled(!model.isDirty)
        Button("Save") { model.save() }
          .keyboardShortcut("s", modifiers: .command)
          .disabled(!model.canSave)
          .buttonStyle(.borderedProminent)
      }
    }
    .padding(12)
  }

  private func icon(for section: Setting.Section) -> String {
    switch section {
    case .general: "gearshape"
    case .glow: "light.max"
    case .shelf: "rectangle.topthird.inset.filled"
    case .apps: "square.grid.2x2"
    }
  }
}
