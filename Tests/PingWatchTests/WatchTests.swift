import Darwin
import Foundation
import Testing

@testable import PingWatch

/// Over real sockets, in the temporary directory. The client blocks, so each one runs on a
/// thread of its own, and stopping the server is what ends a watch that would otherwise wait.
@Suite("Watch")
struct WatchTests {

  private struct Enough: Error {}

  private static func freshPath() -> String {
    NSTemporaryDirectory() + "pw-\(UUID().uuidString.prefix(8)).sock"
  }

  private static func line(_ text: String) -> Data { Data((text + "\n").utf8) }

  /// The first `count` lines a watcher is sent, or how its watch ended before it got them.
  private static func lines(_ count: Int, from path: String) async -> Result<[String], WatchError> {
    await withCheckedContinuation { continuation in
      Thread.detachNewThread {
        var received: [String] = []
        do {
          try WatchClient.watch(path: path) { line in
            received.append(String(decoding: line, as: UTF8.self))
            if received.count == count { throw Enough() }
          }
        } catch is Enough {
          continuation.resume(returning: .success(received))
        } catch let error as WatchError {
          continuation.resume(returning: .failure(error))
        } catch {
          continuation.resume(returning: .failure(.system("\(error)", code: 0)))
        }
      }
    }
  }

  private static func waitFor(_ condition: () -> Bool) async {
    for _ in 0..<200 where !condition() {
      try? await Task.sleep(for: .milliseconds(5))
    }
  }

  @Test("the path is the override, then the temporary directory, then /tmp")
  func path() {
    #expect(WatchSocket.path(environment: ["PING_SOCKET": "/x/p.sock"]) == "/x/p.sock")
    #expect(
      WatchSocket.path(environment: ["TMPDIR": "/var/folders/ab/T/"])
        == "/var/folders/ab/T/ping.sock")
    let long = "/" + String(repeating: "t", count: 120) + "/"
    #expect(WatchSocket.path(environment: ["TMPDIR": long], user: "me") == "/tmp/ping-me.sock")
    #expect(WatchSocket.path(environment: [:], user: "me") == "/tmp/ping-me.sock")
  }

  @Test("a watcher is sent the current reading first, then every one after")
  func currentThenChanges() async throws {
    let path = Self.freshPath()
    let server = WatchServer(path: path)
    try server.start()
    defer { server.stop() }

    server.publish(Self.line("one"))
    async let watched = Self.lines(3, from: path)
    await Self.waitFor { server.watcherCount == 1 }
    server.publish(Self.line("two"))
    server.publish(Self.line("three"))
    #expect(try await watched.get() == ["one", "two", "three"])
  }

  @Test("with nothing listening, a watch is unavailable rather than an empty stream")
  func unavailable() async {
    let path = Self.freshPath()
    #expect(await Self.lines(1, from: path) == .failure(.unavailable(path: path)))
    #expect(!WatchSocket.isListening(at: path))
  }

  @Test("the app going away ends the stream")
  func streamEnds() async throws {
    let path = Self.freshPath()
    let server = WatchServer(path: path)
    try server.start()
    server.publish(Self.line("one"))
    async let watched = Self.lines(2, from: path)
    await Self.waitFor { server.watcherCount == 1 }
    server.stop()
    #expect(await watched == .failure(.streamEnded))
    #expect(!FileManager.default.fileExists(atPath: path))
  }

  @Test("a live socket is refused to a second server; one left by a crash is replaced")
  func takingThePath() throws {
    let path = Self.freshPath()
    let first = WatchServer(path: path)
    try first.start()
    #expect(throws: WatchError.inUse(path: path)) { try WatchServer(path: path).start() }

    // A crash: the file stays, and nothing answers it.
    let orphan = socket(AF_UNIX, SOCK_STREAM, 0)
    first.stop()
    var address = try WatchSocket.address(path)
    let bound = withUnsafePointer(to: &address) {
      $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        bind(orphan, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
      }
    }
    close(orphan)
    #expect(bound == 0)
    #expect(FileManager.default.fileExists(atPath: path))

    let second = WatchServer(path: path)
    try second.start()
    #expect(WatchSocket.isListening(at: path))
    second.stop()
  }

  @Test("a path holding something other than a socket is never unlinked")
  func notASocket() throws {
    let path = Self.freshPath()
    FileManager.default.createFile(atPath: path, contents: Data("mine".utf8))
    defer { unlink(path) }
    #expect(throws: WatchError.inUse(path: path)) { try WatchServer(path: path).start() }
    #expect(FileManager.default.contents(atPath: path) == Data("mine".utf8))
  }

  @Test("a watcher that leaves is let go")
  func leaving() async throws {
    let path = Self.freshPath()
    let server = WatchServer(path: path)
    try server.start()
    defer { server.stop() }
    server.publish(Self.line("one"))
    #expect(try await Self.lines(1, from: path).get() == ["one"])
    await Self.waitFor { server.watcherCount == 0 }
    #expect(server.watcherCount == 0)
  }

  @Test("a watcher that falls behind skips to the newest reading, and never gets half of one")
  func latestWins() async throws {
    let path = Self.freshPath()
    let server = WatchServer(path: path)
    try server.start()
    defer { server.stop() }

    // Connected, and not reading: the socket's buffer fills and the server has to wait.
    let fd = try WatchSocket.connect(to: path)
    defer { close(fd) }
    await Self.waitFor { server.watcherCount == 1 }
    let padding = String(repeating: "x", count: 8 * 1024)
    let total = 400
    for index in 1...total { server.publish(Self.line("\(index) \(padding)")) }

    let lines = try await Task.detached { () throws -> [String] in
      var lines: [String] = []
      var pending = Data()
      var chunk = [UInt8](repeating: 0, count: 64 * 1024)
      while lines.last?.hasPrefix("\(total) ") != true {
        let count = chunk.withUnsafeMutableBytes { read(fd, $0.baseAddress, $0.count) }
        guard count > 0 else { throw WatchError.streamEnded }
        pending.append(contentsOf: chunk[0..<count])
        while let newline = pending.firstIndex(of: 0x0A) {
          lines.append(String(decoding: pending[pending.startIndex..<newline], as: UTF8.self))
          pending = Data(pending[pending.index(after: newline)...])
        }
      }
      return lines
    }.value

    #expect(lines.count < total)
    #expect(lines.allSatisfy { $0.hasSuffix(" " + padding) })
    let numbers = lines.compactMap { Int($0.prefix(while: \.isNumber)) }
    #expect(numbers == numbers.sorted())
  }
}
