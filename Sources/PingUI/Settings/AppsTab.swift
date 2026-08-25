//
//  AppsTab.swift
//  PingUI
//
//  The one surface the settings table cannot describe: `apps.*` is a tree whose
//  middle segment is a Dock title the user invents, and whose leaves are a *cascade* rather than
//  values — every key is optional, and absent means "inherit from `[glow]`" rather than "off".
//
//  So the value rows here are three-state where the table's are two: a row either says something or
//  defers, and "defers" has to be reachable, because a per-app colour that could only be set and
//  never unset would make the cascade write-only.
//
//  Two edits belong to this panel alone. **Subscribing** an app to an effect writes `glow = {}` —
//  presence is opt-in — and unsubscribing takes the whole table out, however it was spelled. That
//  switch is also the app's `enabled`, the two being the same sentence at this level; a badge kind
//  keeps a switch of its own, because `[apps.Messages.glow.dot] enabled = false` — glow for a real
//  count, stay dark for a bare dot — is the one thing no other control here can say.
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

  /// Apps the panel lists that the file has no line for — one just picked from the Dock, one whose
  /// last effect has come off. **Blank is a state a row may be in**, and it is the panel's rather
  /// than the draft's: an app subscribed to nothing is not a configuration.
  @State private var unwritten: [String] = []

  private var apps: [AppConfig] { model.config.apps }

  /// The rows the list shows: the file's apps, and the blank ones under way.
  private var listed: [AppConfig] {
    let written = Set(apps.map(\.name))
    return apps + unwritten.filter { !written.contains($0) }.map { AppConfig(name: $0) }
  }

  var body: some View {
    split
      // An app whose last effect has just come off keeps its row rather than going out from under
      // the pointer mid-edit. `−` is what takes a row away.
      .onChange(of: apps.map(\.name)) { _, names in
        guard let selection = model.selectedApp, !names.contains(selection),
          !unwritten.contains(selection)
        else { return }
        unwritten.append(selection)
      }
      .onAppear {
        let names = listed.map(\.name)
        if let selection = model.selectedApp, names.contains(selection) { return }
        model.selectedApp = names.first
      }
      // Leaving the tab takes the hover with it — the pointer left without an exit event when the
      // row it was over went away with the tab.
      .onDisappear { model.hoveredApp = nil }
  }

  private var split: some View {
    HSplitView {
      list
        .frame(minWidth: 180, idealWidth: 200, maxWidth: 280)
      Group {
        if let name = model.selectedApp, let app = listed.first(where: { $0.name == name }) {
          AppDetail(app: app, model: model)
        } else {
          ContentUnavailableView(
            "No app selected", systemImage: "app.dashed",
            description: Text("Pick an app to say what its badge should do."))
        }
      }
      .frame(minWidth: 320, maxWidth: .infinity, maxHeight: .infinity)
    }
  }

  private var list: some View {
    VStack(spacing: 0) {
      List(selection: $model.selectedApp) {
        ForEach(listed, id: \.name) { app in
          AppRow(
            app: app, badge: engine.snapshot.badges[app.name],
            url: engine.snapshot.appURLs[app.name]
          )
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
          guard let selection = model.selectedApp else { return }
          unwritten.removeAll { $0 == selection }
          // Off the row before it goes, so that taking it away is not read as its last effect
          // coming off — which would put the blank row straight back.
          model.selectedApp = listed.first { $0.name != selection }?.name
          model.apply(.unset(["apps", selection]))
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
      AddAppList(model: model, engine: engine, unwritten: $unwritten, isPresented: $isAdding)
    }
  }
}

private struct AppRow: View {
  let app: AppConfig
  let badge: Badge?
  let url: URL?

  var body: some View {
    HStack(spacing: 6) {
      AppIcon(name: app.name, url: url)
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

/// One app's icon, at the size a list row has room for.
///
/// The stand-in is for an app the file lists that the Dock is not showing: the icon's URL comes
/// with the Dock reading, so an app that has left it has none to draw.
private struct AppIcon: View {
  let name: String
  let url: URL?
  var size: Double = 16

  var body: some View {
    Group {
      if let icon = IconCache.shared.image(name, from: url) {
        Image(nsImage: icon).resizable()
      } else {
        Image(systemName: "app.dashed").resizable().foregroundStyle(.secondary)
      }
    }
    .frame(width: size, height: size)
  }
}

/// What the Dock is showing right now, minus what the file already lists.
private struct AddAppList: View {
  @Bindable var model: SettingsModel
  let engine: EffectEngine
  @Binding var unwritten: [String]
  /// Closed by writing the binding rather than by `dismiss()`, which shuts the popover without
  /// putting the flag back — and a flag still true is a `+` that does nothing.
  @Binding var isPresented: Bool

  private var candidates: [String] {
    let listed = Set(model.config.apps.map(\.name)).union(unwritten)
    return engine.snapshot.dockTitles.filter { !listed.contains($0) }.sorted()
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
                // Nothing is written: which effects the app gets is the question the panel is
                // about, and answering it with a glow nobody asked for is an effect on somebody's
                // screen. The row is blank until a switch there writes one.
                unwritten.append(title)
                model.selectedApp = title
                isPresented = false
              } label: {
                HStack(spacing: 6) {
                  AppIcon(name: title, url: engine.snapshot.appURLs[title])
                  Text(title)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(6)
                .contentShape(Rectangle())
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
          Toggle(
            "",
            isOn: subscription(
              to: "glow", exists: app.glow != nil, optedOut: app.glow?.base.enabled == false)
          )
          .labelsHidden()
        }
        LabeledContent("Shelf") {
          Toggle(
            "",
            isOn: subscription(
              to: "shelf", exists: app.shelf != nil, optedOut: app.shelf?.enabled == false)
          )
          .labelsHidden()
        }
        LabeledContent("Notch") {
          Toggle(
            "",
            isOn: subscription(
              to: "notch", exists: app.notch != nil, optedOut: app.notch?.base.enabled == false)
          )
          .labelsHidden()
        }
      } header: {
        Text(app.name).font(.title3)
      } footer: {
        Text("An effect applies to this app when it is written under it.")
          .font(.caption).foregroundStyle(.secondary)
      }

      if let glow = app.glow {
        Section("Glow") {
          GlowLayerRows(layer: glow.base, at: root.appending("glow"), model: model)
        }
        ForEach(BadgeKind.allCases, id: \.self) { kind in
          BadgeKindSection(
            app: app.name, effect: "glow", kind: kind, layer: glow[kind],
            enabled: glow[kind]?.enabled, inheritedEnabled: glow.base.enabled ?? true, model: model
          ) { layer, key in
            GlowLayerRows(layer: layer, at: key, model: model)
          }
        }
      }

      if let notch = app.notch {
        Section("Notch") {
          NotchRows(
            layer: notch.base, inherited: ResolvedNotchItem.defaultColor, inheritable: false,
            at: root.appending("notch"), model: model)
        }
        ForEach(BadgeKind.allCases, id: \.self) { kind in
          BadgeKindSection(
            app: app.name, effect: "notch", kind: kind, layer: notch[kind],
            enabled: notch[kind]?.enabled, inheritedEnabled: notch.base.enabled ?? true,
            model: model
          ) { layer, key in
            NotchRows(
              layer: layer, inherited: notch.base.color ?? ResolvedNotchItem.defaultColor,
              inheritable: true, at: key, model: model)
          }
        }
      }
    }
    .formStyle(.grouped)
  }

  /// The app's one switch for an effect. Writing `{}` subscribes and taking the table out
  /// unsubscribes; an `enabled = false` the file carries is the same answer said differently, so it
  /// reads as off and switching back on removes it rather than writing `true` beside it.
  private func subscription(to effect: String, exists: Bool, optedOut: Bool) -> Binding<Bool> {
    Binding(
      get: { exists && !optedOut },
      set: { wanted in
        let key = root.appending(effect)
        if !wanted {
          model.apply(.unset(key))
        } else if optedOut {
          model.apply(.unset(key.appending("enabled")))
        } else {
          model.apply(.key(key, .emptyTable()))
        }
      })
  }
}

/// A `count` or `dot` override: the same keys again, one level deeper. Written once for both
/// effects, because the glow's cascade and the notch's differ in their keys and in nothing else.
private struct BadgeKindSection<Layer, Rows: View>: View {
  let app: String
  let effect: String
  let kind: BadgeKind
  /// What this kind overrides, or `nil` when it does not override at all.
  let layer: Layer?
  /// What this kind says about being drawn at all, and what the app's own layer says when it says
  /// nothing. The switch needs both: "on" here means "on where the app is off" as readily as it
  /// means the plain thing.
  let enabled: Bool?
  let inheritedEnabled: Bool
  @Bindable var model: SettingsModel
  @ViewBuilder let rows: (Layer, TOMLKey) -> Rows

  private var key: TOMLKey { ["apps", app, effect, kind.rawValue] }

  private var title: String {
    kind == .count ? "When the badge is a number" : "When the badge is a bare dot"
  }

  var body: some View {
    Section(title) {
      LabeledContent("Override") {
        Toggle("", isOn: override).labelsHidden()
      }
      if let layer {
        LabeledContent(effect.capitalized) {
          Toggle("", isOn: shows).labelsHidden()
        }
        rows(layer, key)
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
        model.apply(.expand(["apps", app, effect]))
        model.apply(.key(key, .emptyTable()))
      })
  }

  /// Whether this badge kind is drawn. Agreeing with the app is written as *nothing*, so the only
  /// line this produces is the disagreement — which is the whole point of the key.
  private var shows: Binding<Bool> {
    Binding(
      get: { enabled ?? inheritedEnabled },
      set: { wanted in
        let line = key.appending("enabled")
        guard wanted != inheritedEnabled else {
          model.apply(.unset(line))
          return
        }
        model.apply(.expand(["apps", app, effect]))
        model.apply(.key(line, .bool(wanted)))
      })
  }
}

/// The one key an indicator has beyond whether it is drawn at all. `color` is the point of the
/// effect — indicators are told apart by nothing else.
private struct NotchRows: View {
  let layer: NotchLayer
  /// The colour this level shows when it says nothing, which is also what a newly-written key
  /// starts at so that turning the row on changes nothing by itself.
  let inherited: PingColor
  /// Whether saying nothing is a *choice* here. Under a badge kind it is — the app's own colour is
  /// there to defer to. At the app's own level only the built-in red is above it, `[notch]` carrying
  /// no colour of its own, so there is nothing to offer.
  let inheritable: Bool
  let at: TOMLKey
  @Bindable var model: SettingsModel

  var body: some View {
    if inheritable {
      InheritableRow(label: "Color", isSet: layer.color != nil, key: at.appending("color")) {
        ColorWell(color: color(layer.color ?? inherited))
      } write: {
        model.apply(.key(at.appending("color"), .string(inherited.written)))
      }
    } else {
      LabeledContent("Color") {
        ColorWell(color: color(layer.color ?? inherited))
      }
    }
  }

  private func color(_ current: PingColor) -> Binding<PingColor> {
    Binding(
      get: { current },
      set: { picked in
        let key = at.appending("color")
        // With no checkbox to take the line out, choosing the colour the indicator already draws is
        // what does — the rule the rest of the window keeps, one level deeper.
        if !inheritable, picked == inherited {
          model.apply(.unset(key))
        } else {
          model.apply(.key(key, .string(picked.written)))
        }
      })
  }
}

/// The four glow keys a level can shade, each of which may also say *nothing* and inherit.
private struct GlowLayerRows: View {
  let layer: GlowLayer
  let at: TOMLKey
  @Bindable var model: SettingsModel

  var body: some View {
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
      NumberRow(value: number(layer.size ?? 1.0, "size"), range: 0.25...1.0, step: 0.05)
    } write: {
      model.apply(.key(at.appending("size"), .number(inherited.size)))
    }

    InheritableRow(label: "Opacity", isSet: layer.opacity != nil, key: at.appending("opacity")) {
      NumberRow(value: number(layer.opacity ?? 1.0, "opacity"), range: 0.0...1.0, step: 0.05)
    } write: {
      model.apply(.key(at.appending("opacity"), .number(inherited.opacity)))
    }
  }

  /// What this level would show if it said nothing — the cascade above it, which is also the value
  /// a newly-written key starts at so that turning a row on changes nothing by itself.
  private var inherited: ResolvedGlow {
    ResolvedGlow.builtin.applying(model.config.glow.defaults)
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
