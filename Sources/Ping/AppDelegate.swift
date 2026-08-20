//
//  AppDelegate.swift
//  Ping
//
//  Everything that runs: read the file, read the Dock, resolve, render. Four tasks and no
//  observation re-arming.
//

import AppKit
import PingConfig
import PingCore
import PingUI
import ServiceManagement
import SwiftUI
import os

private let logger = Logger(subsystem: "Ping", category: "app")

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

  let engine = EffectEngine()
  lazy var settings = SettingsModel(engine: engine)

  private let glow = GlowRenderer()
  private let shelf = ShelfRenderer()
  private let monitor = BadgeMonitor()
  private let loader = ConfigLoader()
  private var tasks: [Task<Void, Never>] = []

  override init() {
    super.init()
    FontLoader.load()
    reloadConfig()
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    watchFrontmostApp()

    // One loop, watching one derived value.
    tasks.append(
      Task { @MainActor [engine, glow, shelf] in
        var last: RenderState?
        for await state in Observations({ engine.renderState }) {
          guard state != last else { continue }
          last = state
          glow.render(state)
          shelf.render(state)
        }
      })

    tasks.append(
      Task { @MainActor [engine, monitor] in
        let interval = { @MainActor in
          Duration.milliseconds(engine.config.general.pollIntervalMS)
        }
        for await snapshot in monitor.snapshots(interval: interval) {
          engine.apply(snapshot)
        }
      })

    tasks.append(
      Task { @MainActor [glow, shelf] in
        for await _ in ScreenTopology.changes() {
          glow.screenParametersChanged()
          shelf.screenParametersChanged()
        }
      })

    // The file is the settings, so it is watched rather than polled: a vnode source on the
    // file *and* on its directory, since an atomic save is invisible to the first and an
    // in-place rewrite to the second. A settings-window save re-enters here as an ordinary
    // reload of the config it just wrote, and is dropped as unchanged.
    tasks.append(
      Task { @MainActor [weak self] in
        guard let loader = self?.loader else { return }
        for await result in loader.changes() {
          self?.apply(result)
        }
      })
  }

  func applicationWillTerminate(_ notification: Notification) {
    for task in tasks { task.cancel() }
    monitor.stop()
  }

  private func reloadConfig() {
    apply(loader.load())
  }

  private func apply(_ result: Result<ParsedConfig, ConfigLoadError>) {
    engine.apply(result.mapError { $0 as any Error })
    if case .failure(let error) = result {
      logger.error("Config refused, keeping the last good one: \(error)")
    }
    syncLaunchAtLogin()
  }

  /// The file wins on load, and `SMAppService` is synced to it.
  private func syncLaunchAtLogin() {
    let wanted = engine.config.general.launchAtLogin
    let service = SMAppService.mainApp
    do {
      if wanted && service.status != .enabled {
        try service.register()
      } else if !wanted && service.status == .enabled {
        try service.unregister()
      }
    } catch {
      logger.error("Could not sync launch-at-login: \(error)")
    }
  }

  private func watchFrontmostApp() {
    NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.didActivateApplicationNotification,
      object: nil, queue: .main
    ) { [weak self] notification in
      let app =
        notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
      let name = app?.localizedName
      let bundleID = app?.bundleIdentifier
      Task { @MainActor in
        self?.engine.runtime.frontmostAppName = name
        self?.engine.runtime.frontmostBundleID = bundleID
      }
    }
    engine.runtime.frontmostAppName = NSWorkspace.shared.frontmostApplication?.localizedName
    engine.runtime.frontmostBundleID =
      NSWorkspace.shared.frontmostApplication?.bundleIdentifier
  }
}
