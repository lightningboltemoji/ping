import Foundation
import Testing

/// The module graph cannot forbid these on its own — `PingConfig` links Foundation, and
/// Foundation on macOS can reach a lot — so the fence is a test that reads the sources.
/// The rule it enforces: no `NSColor`, and no AppKit at all, below PingUI.
@Suite("Import fence")
struct ImportFenceTests {

  private static let sourcesDirectory = URL(filePath: #filePath)
    .deletingLastPathComponent()  // PingConfigTests
    .deletingLastPathComponent()  // Tests
    .deletingLastPathComponent()  // repo root
    .appending(path: "Sources")

  /// Prose is allowed to say "NSColor"; code is not.
  private func code(in file: URL) throws -> String {
    try String(contentsOf: file, encoding: .utf8)
      .split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
      .map { line in
        guard let comment = line.range(of: "//") else { return String(line) }
        return String(line[line.startIndex..<comment.lowerBound])
      }
      .joined(separator: "\n")
  }

  private func swiftFiles(in target: String) throws -> [URL] {
    let root = Self.sourcesDirectory.appending(path: target)
    let contents = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
    return (contents?.allObjects as? [URL] ?? []).filter { $0.pathExtension == "swift" }
  }

  @Test("PingConfig imports no UI, and names no NSColor")
  func configHasNoUI() throws {
    let forbidden = ["import AppKit", "import SwiftUI", "import Cocoa", "NSColor"]
    for file in try swiftFiles(in: "PingConfig") {
      let text = try code(in: file)
      for needle in forbidden {
        #expect(!text.contains(needle), "\(file.lastPathComponent) contains '\(needle)'")
      }
    }
  }

  @Test("PingWatch imports Foundation and Darwin and nothing else, so the CLI stays small")
  func watchIsBare() throws {
    for file in try swiftFiles(in: "PingWatch") {
      let imports = try code(in: file)
        .split(whereSeparator: \.isNewline)
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { $0.hasPrefix("import ") }
      #expect(
        Set(imports).isSubset(of: ["import Foundation", "import Darwin"]),
        "\(file.lastPathComponent) imports \(imports)")
    }
  }

  @Test("PingCore reaches AppKit only for the accessibility and screen work")
  func coreHasNoSwiftUI() throws {
    for file in try swiftFiles(in: "PingCore") {
      let text = try code(in: file)
      #expect(!text.contains("import SwiftUI"), "\(file.lastPathComponent) imports SwiftUI")
      #expect(!text.contains("NSColor"), "\(file.lastPathComponent) names NSColor")
    }
  }
}
