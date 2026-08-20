//
//  DockReader.swift
//  PingCore
//
//  The accessibility traversal, kept close to verbatim from the pre-rewrite `DockHelper`. It
//  reads every application item once per poll rather than only the
//  configured ones, so the snapshot is a fact about the Dock and not about the config.
//

import AppKit
@preconcurrency import ApplicationServices
import Foundation

public enum DockReader {

  /// Every badge the Dock is currently showing, plus what is in the Dock at all — the
  /// settings picker needs the titles whether or not they are badged.
  @MainActor
  public static func read() -> BadgeSnapshot {
    var snapshot = BadgeSnapshot()
    for item in list() {
      snapshot.dockTitles.append(item.title)
      if let url = item.appURL {
        snapshot.appURLs[item.title] = url
      }
      if let badge = item.badge() {
        snapshot.badges[item.title] = badge
      }
    }
    snapshot.dockTitles.sort()
    return snapshot
  }

  public static func list() -> [DockItem] {
    var result: [DockItem] = []

    let dockApps = NSRunningApplication.runningApplications(
      withBundleIdentifier: "com.apple.dock"
    )
    guard let dockApp = dockApps.first else { return result }

    let axDockApp = AXUIElementCreateApplication(dockApp.processIdentifier)

    guard
      let dockList = copyAXUIElement(
        from: axDockApp,
        role: kAXListRole as CFString,
        at: 0
      )
    else {
      return result
    }

    var children: CFTypeRef?
    let error = AXUIElementCopyAttributeValue(
      dockList,
      kAXChildrenAttribute as CFString,
      &children
    )

    guard error == .success, let childrenArray = children else {
      return result
    }

    let elementsArray = childrenArray as! CFArray

    for i in 0..<CFArrayGetCount(elementsArray) {
      guard let element = CFArrayGetValueAtIndex(elementsArray, i) else { continue }
      let axElement = Unmanaged<AXUIElement>.fromOpaque(element)
        .takeUnretainedValue()

      // Only include actual application dock items
      var subrole: CFTypeRef?
      AXUIElementCopyAttributeValue(
        axElement,
        kAXSubroleAttribute as CFString,
        &subrole
      )
      guard let subroleString = subrole as? String,
        subroleString == "AXApplicationDockItem"
      else { continue }

      var title: CFTypeRef?
      let titleError = AXUIElementCopyAttributeValue(
        axElement,
        kAXTitleAttribute as CFString,
        &title
      )

      if titleError == .success, let titleString = title as? String {
        guard
          let axEl = copyAXUIElement(
            from: dockList,
            role: kAXDockItemRole as CFString,
            at: i
          )
        else { continue }
        result.append(
          DockItem(
            title: titleString,
            axElement: axEl
          )
        )
      }

    }
    return result
  }

  private static func copyAXUIElement(
    from container: AXUIElement,
    role: CFString?,
    at index: Int
  ) -> AXUIElement? {
    var children: CFTypeRef?
    let error = AXUIElementCopyAttributeValue(
      container,
      kAXChildrenAttribute as CFString,
      &children
    )

    guard error == .success, let childrenArray = children else {
      return nil
    }

    let elementsArray = childrenArray as! CFArray
    var currentIndex = -1

    for i in 0..<CFArrayGetCount(elementsArray) {
      guard let element = CFArrayGetValueAtIndex(elementsArray, i) else { continue }
      let axElement = Unmanaged<AXUIElement>.fromOpaque(element)
        .takeUnretainedValue()

      if let role = role {
        var elementRole: CFTypeRef?
        let roleError = AXUIElementCopyAttributeValue(
          axElement,
          kAXRoleAttribute as CFString,
          &elementRole
        )

        if roleError == .success, let roleStr = elementRole {
          if CFStringCompare((roleStr as! CFString), role, [])
            == .compareEqualTo
          {
            currentIndex += 1
          }
        } else {
          continue
        }
      } else {
        currentIndex += 1
      }

      if currentIndex == index {
        return axElement
      }
    }

    return nil
  }
}
