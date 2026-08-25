//
//  PingResources.swift
//  PingUI
//
//  The font and the menu bar icon live here, in the one target that draws.
//

import AppKit
import Foundation

public enum PingResources {
  /// SwiftPM's resource bundle for `PingUI`, searched for rather than reached through the generated
  /// `Bundle.module`, whose shape — and so where it looks — is the toolchain's choice. The three
  /// roots are every layout Ping runs in: the `.app`, a test bundle, and the binary's own directory.
  public static let bundle: Bundle = {
    let name = "Ping_PingUI"
    let roots = [
      Bundle.main.resourceURL,
      Bundle(for: Anchor.self).resourceURL,
      Bundle.main.bundleURL,
    ]
    for root in roots.compactMap({ $0?.appendingPathComponent(name + ".bundle") }) {
      if let bundle = Bundle(url: root) { return bundle }
    }
    // `preconditionFailure` would trap without the message under `-O`.
    fatalError("\(name).bundle is in none of: \(roots.compactMap { $0?.path })")
  }()

  /// `Bundle(for:)` needs a class from this target to read a bundle off; that is Anchor's whole use.
  private final class Anchor {}

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
