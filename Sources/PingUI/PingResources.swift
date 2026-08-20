//
//  PingResources.swift
//  PingUI
//
//  The font and the menu bar icon live here, in the one target that draws.
//

import AppKit
import Foundation

public enum PingResources {
  public static let bundle = Bundle.module

  /// The menu bar bell, as a template image so it follows the menu bar's own appearance.
  public static var menuBarIcon: NSImage {
    guard
      let url = bundle.url(forResource: "Bell", withExtension: "svg"),
      let image = NSImage(contentsOf: url)
    else {
      return NSImage(systemSymbolName: "bell.fill", accessibilityDescription: "Ping")!
    }
    image.isTemplate = true
    image.size = NSSize(width: 18, height: 18)
    return image
  }
}
