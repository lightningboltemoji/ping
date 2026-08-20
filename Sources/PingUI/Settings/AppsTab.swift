//
//  AppsTab.swift
//  PingUI
//
//  The one surface the settings table cannot describe: `apps.*` is a tree whose
//  middle segment is a Dock title the user invents, and whose leaves are a *cascade* rather than
//  values — every key is optional, and absent means "inherit from `[glow]`" rather than "off".
//
//  So the controls here are three-state where the table's are two: a row either says something or
//  defers, and "defers" has to be reachable, because a per-app colour that could only be set and
//  never unset would make the cascade write-only.
//
//  Two edits belong to this panel alone. **Subscribing** an app to an effect writes `glow = {}` —
//  presence is opt-in — and unsubscribing takes the whole table out, however it was spelled.
//  **A badge-kind override** needs the braces taken apart first, because TOML will not let a header
//  reopen an inline table; that is `expand`, and it is the one edit that moves lines.
//
//  The selection lives on the model rather than here, because it is also the preview's subject:
//  whichever app's panel is open is the app on screen, and a hover previews a row ahead of
//  selecting it. A badge-kind section previews its kind while the pointer is in it — an override
//  for a badge the Dock is not showing right now has no other way to be seen.
//

import PingConfig
import PingCore
import SwiftUI

struct AppsTab: View {
  @Bindable var model: SettingsModel
  let engine: EffectEngine

  @State private var isAdding = false

  private var apps: [AppConfig] { model.config.apps }

  var body: some View {
    HSplitView {
      list
        .frame(minWidth: 180, idealWidth: 200, maxWidth: 280)
      Group {
        if let name = model.selectedApp, let app = apps.first(where: { $0.name == name }) {
          AppDetail(app: app, model: model)
        } else {
          ContentUnavailableView(
            "No app selected", systemImage: "app.dashed",
            description: Text("Pick an app to say what its badge should do."))
        }
      }
      .frame(minWidth: 320, maxWidth: .infinity, maxHeight: .infinity)
    }
    .onChange(of: apps.map(\.name)) { _, names in
      if let selection = model.selectedApp, !names.contains(selection) {
        model.selectedApp = names.first
      }
      if model.selectedApp == nil { model.selectedApp = names.first }
    }
    .onAppear { model.selectedApp = model.selectedApp ?? apps.first?.name }
    // Leaving the tab takes the hover with it — the pointer left without an exit event when the
    // row it was over went away with the tab.
    .onDisappear { model.hoveredApp = nil }
  }

  private var list: some View {
    VStack(spacing: 0) {
      List(selection: $model.selectedApp) {
        ForEach(apps, id: \.name) { app in
          AppRow(app: app, badge: engine.snapshot.badges[app.name])
            .tag(app.name)
            // Hovering shows what that app's badge would look like, without waiting for a real
            // notification and without having to select it first. The exit is guarded
            // because entering the next row arrives before leaving this one.
            .onHover { inside in
              if inside {
                model.hoveredApp = app.name
              } else if model.hoveredApp == app.name {
                model.hoveredApp = nil
              }
            }
        }
      }
      Divider()
      HStack(spacing: 4) {
        Button {
          isAdding = true
        } label: {
          Image(systemName: "plus")
        }
        .help("Add an app from the Dock")
        Button {
          if let selection = model.selectedApp { model.apply(.unset(["apps", selection])) }
        } label: {
          Image(systemName: "minus")
        }
        .disabled(model.selectedApp == nil)
        .help("Stop watching this app")
        Spacer()
      }
      .buttonStyle(.borderless)
      .padding(6)
    }
    .popover(isPresented: $isAdding, arrowEdge: .bottom) {
      AddAppList(model: model, engine: engine)
    }
  }
}

private struct AppRow: View {
  let app: AppConfig
  let badge: Badge?

  var body: some View {
    HStack(spacing: 6) {
      Text(app.name).lineLimit(1)
      Spacer(minLength: 4)
      if let badge {
        Text(badge.raw.isEmpty ? "●" : badge.raw)
          .font(.caption2.monospacedDigit())
          .foregroundStyle(.white)
          .padding(.horizontal, 5)
          .padding(.vertical, 1)
          .background(Capsule().fill(.red))
      }
    }
  }
}

/// What the Dock is showing right now, minus what the file already lists.
private struct AddAppList: View {
  @Bindable var model: SettingsModel
  let engine: EffectEngine

  private var candidates: [String] {
    let known = Set(model.config.apps.map(\.name))
    return engine.snapshot.dockTitles.filter { !known.contains($0) }.sorted()
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Add from the Dock").font(.headline).padding(8)
      Divider()
      if candidates.isEmpty {
        Text("Every app in the Dock is already listed.")
          .foregroundStyle(.secondary)
          .padding(8)
      } else {
        ScrollView {
          VStack(alignment: .leading, spacing: 0) {
            ForEach(candidates, id: \.self) { title in
              Button {
                // Subscribing to the glow is what makes the app worth listing at all; the shelf is
                // a second choice, made in the detail panel.
                model.apply(.key(["apps", title, "glow"], .emptyTable()))
                model.selectedApp = title
              } label: {
                Text(title).frame(maxWidth: .infinity, alignment: .leading).padding(6)
              }
              .buttonStyle(.plain)
            }
          }
        }
        .frame(maxHeight: 280)
      }
    }
    .frame(width: 240)
  }
}

//
// One app's settings.

private struct AppDetail: View {
  let app: AppConfig
  @Bindable var model: SettingsModel

  private var root: TOMLKey { ["apps", app.name] }

  var body: some View {
    Form {
      Section {
        LabeledContent("Glow") {
          Toggle("", isOn: subscription(to: "glow", isOn: app.glow != nil)).labelsHidden()
        }
        LabeledContent("Shelf") {
          Toggle("", isOn: subscription(to: "shelf", isOn: app.shelf != nil)).labelsHidden()
        }
        LabeledContent("Notch") {
          Toggle("", isOn: subscription(to: "notch", isOn: app.notch != nil)).labelsHidden()
        }
      } header: {
        Text(app.name).font(.title3)
      } footer: {
        Text("An effect applies to this app when it is written under it.")
          .font(.caption).foregroundStyle(.secondary)
      }

      if app.glow != nil {
        Section("Glow") {
          GlowLayerRows(
            layer: app.glow?.base ?? GlowLayer(), at: root.appending("glow"), model: model)
        }
        ForEach(BadgeKind.allCases, id: \.self) { kind in
          BadgeKindSection(app: app, kind: kind, model: model)
        }
      }

      if app.notch != nil {
        Section("Notch") {
          NotchRows(notch: app.notch ?? AppNotch(), at: root.appending("notch"), model: model)
        }
      }
    }
    .formStyle(.grouped)
  }

  /// Writing `{}` subscribes; taking the table out unsubscribes. Neither is a value with a default,
  /// which is why this is not a `Setting`.
  private func subscription(to effect: String, isOn: Bool) -> Binding<Bool> {
    Binding(
      get: { isOn },
      set: { wanted in
        let key = root.appending(effect)
        model.apply(wanted ? .key(key, .emptyTable()) : .unset(key))
      })
  }
}

/// A `count` or `dot` override: the same five keys again, one level deeper.
private struct BadgeKindSection: View {
  let app: AppConfig
  let kind: BadgeKind
  @Bindable var model: SettingsModel

  private var layer: GlowLayer? {
    kind == .count ? app.glow?.count : app.glow?.dot
  }
  private var key: TOMLKey { ["apps", app.name, "glow", kind.rawValue] }

  private var title: String {
    kind == .count ? "When the badge is a number" : "When the badge is a bare dot"
  }

  var body: some View {
    Section(title) {
      LabeledContent("Override") {
        Toggle("", isOn: override).labelsHidden()
      }
      if let layer {
        GlowLayerRows(layer: layer, at: key, model: model)
      }
    }
    // While the pointer is in here, the preview badge is this kind — otherwise a `dot` override
    // could only be seen by waiting for an app to show a bare dot.
    .onHover { inside in
      if inside {
        model.previewBadge = kind
      } else if model.previewBadge == kind {
        model.previewBadge = .count
      }
    }
  }

  private var override: Binding<Bool> {
    Binding(
      get: { layer != nil },
      set: { wanted in
        guard wanted else {
          model.apply(.unset(key))
          return
        }
        // TOML will not let `[apps.X.glow.dot]` reopen a `glow = { … }`, so the braces come apart
        // first. Harmless when the file already writes the long form — `expand` leaves a table it
        // does not find between braces alone.
        model.apply(.expand(["apps", app.name, "glow"]))
        model.apply(.key(key, .emptyTable()))
      })
  }
}

/// The two the notch takes per app. `color` is the point of the effect — indicators are told
/// apart by nothing else — and its default is the Dock badge's own red.
private struct NotchRows: View {
  let notch: AppNotch
  let at: TOMLKey
  @Bindable var model: SettingsModel

  var body: some View {
    InheritableRow(label: "Enabled", isSet: notch.enabled != nil, key: at.appending("enabled")) {
      Toggle("", isOn: enabled(notch.enabled ?? true)).labelsHidden()
    } write: {
      model.apply(.key(at.appending("enabled"), .bool(true)))
    }

    InheritableRow(label: "Color", isSet: notch.color != nil, key: at.appending("color")) {
      ColorWell(color: color(notch.color ?? ResolvedNotchItem.defaultColor))
    } write: {
      model.apply(.key(at.appending("color"), .string(ResolvedNotchItem.defaultColor.written)))
    }
  }

  private func enabled(_ current: Bool) -> Binding<Bool> {
    Binding(
      get: { current },
      set: { model.apply(.key(at.appending("enabled"), .bool($0))) })
  }

  private func color(_ current: PingColor) -> Binding<PingColor> {
    Binding(
      get: { current },
      set: { model.apply(.key(at.appending("color"), .string($0.written))) })
  }
}

/// The five glow keys, each of which may also say *nothing* and inherit.
private struct GlowLayerRows: View {
  let layer: GlowLayer
  let at: TOMLKey
  @Bindable var model: SettingsModel

  var body: some View {
    InheritableRow(label: "Enabled", isSet: layer.enabled != nil, key: at.appending("enabled")) {
      Toggle("", isOn: bool(layer.enabled ?? true, "enabled")).labelsHidden()
    } write: {
      model.apply(.key(at.appending("enabled"), .bool(true)))
    }

    InheritableRow(label: "Color", isSet: layer.color != nil, key: at.appending("color")) {
      ColorWell(color: color(layer.color ?? .named(.green)))
    } write: {
      model.apply(.key(at.appending("color"), .string(inherited.color.written)))
    }

    InheritableRow(label: "Edge", isSet: layer.edge != nil, key: at.appending("edge")) {
      Picker("", selection: edge(layer.edge ?? .bottom)) {
        ForEach(PingConfig.Edge.allCases, id: \.self) { edge in
          Text(edge.rawValue.capitalized).tag(edge)
        }
      }
      .labelsHidden()
      .frame(maxWidth: 160)
    } write: {
      model.apply(.key(at.appending("edge"), .string(inherited.edge.rawValue)))
    }

    InheritableRow(label: "Size", isSet: layer.size != nil, key: at.appending("size")) {
      NumberRow(value: number(layer.size ?? 1.0, "size"), range: 0.25...1.0)
    } write: {
      model.apply(.key(at.appending("size"), .number(inherited.size)))
    }

    InheritableRow(label: "Opacity", isSet: layer.opacity != nil, key: at.appending("opacity")) {
      NumberRow(value: number(layer.opacity ?? 1.0, "opacity"), range: 0.0...1.0)
    } write: {
      model.apply(.key(at.appending("opacity"), .number(inherited.opacity)))
    }
  }

  /// What this level would show if it said nothing — the cascade above it, which is also the value
  /// a newly-written key starts at so that turning a row on changes nothing by itself.
  private var inherited: ResolvedGlow {
    ResolvedGlow.builtin.applying(model.config.glow.defaults)
  }

  private func bool(_ current: Bool, _ name: String) -> Binding<Bool> {
    Binding(
      get: { current },
      set: { model.apply(.key(at.appending(name), .bool($0))) })
  }

  private func number(_ current: Double, _ name: String) -> Binding<Double> {
    Binding(
      get: { current },
      set: { model.apply(.key(at.appending(name), .number($0))) })
  }

  private func color(_ current: PingColor) -> Binding<PingColor> {
    Binding(
      get: { current },
      set: { model.apply(.key(at.appending("color"), .string($0.written))) })
  }

  private func edge(_ current: PingConfig.Edge) -> Binding<PingConfig.Edge> {
    Binding(
      get: { current },
      set: { model.apply(.key(at.appending("edge"), .string($0.rawValue))) })
  }
}

/// A row that can say nothing.
///
/// The checkbox is the *presence of the line*, and the control beside it is its value. Without the
/// first, a per-app colour could be set and never unset, and the cascade would be write-only.
private struct InheritableRow<Control: View>: View {
  let label: String
  let isSet: Bool
  let key: TOMLKey
  @ViewBuilder let control: Control
  let write: () -> Void

  @Environment(SettingsModel.self) private var model

  var body: some View {
    LabeledContent {
      HStack(spacing: 8) {
        if isSet {
          control
        } else {
          Text("inherited").foregroundStyle(.secondary).font(.callout)
        }
        Toggle("", isOn: presence).labelsHidden().toggleStyle(.checkbox)
          .help(isSet ? "Stop overriding this" : "Override this for this app")
      }
    } label: {
      Text(label)
    }
  }

  private var presence: Binding<Bool> {
    Binding(
      get: { isSet },
      set: { wanted in
        if wanted { write() } else { model.apply(.unset(key)) }
      })
  }
}
