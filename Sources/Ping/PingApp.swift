//
//  PingApp.swift
//  Ping
//
//  Created by Tanner on 9/13/25.
//
//  Configuration is `~/.config/ping/ping.toml`, and nothing else.
//

import PingCore
import PingUI
import SwiftUI

@main
struct PingApp: App {

  @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

  var body: some Scene {
    WindowGroup("Accessibility") {
      AccessibilityView()
    }
    .windowLevel(.floating)
    .windowStyle(.hiddenTitleBar)
    .windowResizability(.contentSize)

    MenuBarExtra {
      MenuBarContent(engine: appDelegate.engine)
    } label: {
      Image(nsImage: PingResources.menuBarIcon)
    }

    Settings {
      SettingsView(model: appDelegate.settings, engine: appDelegate.engine)
    }
  }
}
