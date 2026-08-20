//
//  EffectResolver.swift
//  PingCore
//
//  (Config, BadgeSnapshot, RuntimeState) -> RenderState, and nothing else. Pure, so the
//  cascade's whole truth table can be tested headless (IMPLEMENTATION.md §4).
//

import Foundation
import PingConfig

public enum EffectResolver {

  public static func renderState(
    config: Config,
    snapshot: BadgeSnapshot,
    runtime: RuntimeState,
    now: Date
  ) -> RenderState {
    var state = RenderState()
    state.pulse = config.glow.pulse
    state.monitors = config.general.monitors

    // A preview is the user asking to see a setting, so it answers to the settings alone:
    // no snooze, no acknowledgement, no focus suppression standing in the way. It is also
    // scoped — the tab being edited says which effects it is about, and the rest stay off.
    let preview = runtime.preview
    let previewing = preview != nil
    let effective = preview?.snapshot ?? snapshot
    let effects = preview?.effects ?? .all
    state.isPreview = previewing

    if !previewing && runtime.isSnoozed(at: now) { return state }

    var shelfItems: [ShelfItem] = []
    var notchItems: [NotchItem] = []

    // Stand-ins are only ever *added*: an app the file already describes is drawn the way the
    // file describes it, so a preview cannot quietly contradict the config it is previewing.
    let samples = (preview?.samples ?? []).filter { config.app(named: $0.name) == nil }

    for app in config.apps + samples {
      guard let badge = effective.badges[app.name] else { continue }

      if !previewing {
        if runtime.isCovered(app.name, badge: badge) { continue }
        if config.general.suppressWhenFocused && isFrontmost(app, runtime: runtime) { continue }
      }

      if effects.contains(.glow), let glow = config.resolvedGlow(for: app, badge: badge.kind) {
        state.glows.append(GlowInstance(appName: app.name, glow: glow))
      }
      if effects.contains(.shelf), config.shelfShows(app) {
        shelfItems.append(
          ShelfItem(appName: app.name, badge: badge, appURL: effective.appURLs[app.name]))
      }
      if effects.contains(.notch), let item = config.resolvedNotch(for: app, badge: badge.kind) {
        notchItems.append(
          NotchItem(
            appName: app.name, badge: badge, color: item.color, style: item.style,
            appURL: effective.appURLs[app.name]))
      }
    }

    if !shelfItems.isEmpty {
      state.shelf = ShelfState(settings: config.shelf, items: shelfItems)
    }
    // The strip is also on screen with nothing in it: `always-show` is the stand-in standing
    // by, and a preview of the notch alone must never be an empty screen.
    if config.notch.enabled,
      !notchItems.isEmpty || config.notch.alwaysShow || preview?.effects == .notch
    {
      state.notch = NotchState(settings: config.notch, items: notchItems)
    }
    return state
  }

  /// `NSRunningApplication.localizedName` and the Dock title usually agree but are not
  /// guaranteed to, so an app that declares `bundle-id` is matched on that instead.
  private static func isFrontmost(_ app: AppConfig, runtime: RuntimeState) -> Bool {
    if let bundleID = app.bundleID, let frontmostBundleID = runtime.frontmostBundleID {
      return bundleID == frontmostBundleID
    }
    return runtime.frontmostAppName == app.name
  }
}
