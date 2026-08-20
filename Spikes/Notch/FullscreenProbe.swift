// FullscreenProbe.swift — a stand-in for "the app you were working in".
//
//   swift Spikes/Notch/FullscreenProbe.swift [seconds=12]
//
// Run alongside NotchDemo. It opens one window, takes it full-screen (which moves it to its
// own space, where the menu bar is hidden), holds, and quits. The question it answers is
// PRINCIPLES.md §4's: does the effect belong to the screen, or did it stay behind on the
// space it was made on — which is exactly the notification most worth not missing.

import AppKit

var opts: [String: String] = [:]
for arg in CommandLine.arguments.dropFirst() {
  let parts = arg.split(separator: "=", maxSplits: 1)
  if parts.count == 2 { opts[String(parts[0])] = String(parts[1]) }
}
let seconds = opts["seconds"].flatMap(Double.init) ?? 12

_ = NSApplication.shared
NSApp.setActivationPolicy(.regular)

let w = NSWindow(
  contentRect: NSRect(x: 200, y: 200, width: 900, height: 600),
  styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
w.title = "Fullscreen probe"
w.backgroundColor = NSColor.systemIndigo
w.collectionBehavior.insert(.fullScreenPrimary)
w.makeKeyAndOrderFront(nil)
NSApp.activate(ignoringOtherApps: true)

Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { _ in
  w.toggleFullScreen(nil)
  print("went full-screen")
}
Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { _ in NSApp.terminate(nil) }
print("up for \(seconds)s")
NSApp.run()
