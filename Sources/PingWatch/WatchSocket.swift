//
//  WatchSocket.swift
//  PingWatch
//
//  Where `watch` meets the app: one Unix socket per user, which the app listens on and the CLI
//  dials. The framing is JSON lines — one whole reading of the Dock, one `\n`.
//

import Darwin
import Foundation

public enum WatchSocket {

  /// Moves the socket: the escape hatch for tests, and for two Pings side by side.
  public static let environmentKey = "PING_SOCKET"

  public static let fileName = "ping.sock"

  /// `sockaddr_un.sun_path` is 104 bytes including the NUL, so a longer path cannot be bound.
  static let maxPathBytes = 103

  /// `PING_SOCKET`, then `$TMPDIR` (on macOS the per-user, `0700` `/var/folders/…/T/`), then
  /// `/tmp/ping-<user>.sock`.
  public static func path(
    environment: [String: String] = ProcessInfo.processInfo.environment,
    user: String = NSUserName()
  ) -> String {
    if let override = environment[environmentKey], !override.isEmpty { return override }
    if let temporary = environment["TMPDIR"], !temporary.isEmpty {
      let path = URL(filePath: temporary, directoryHint: .isDirectory)
        .appending(path: fileName).path(percentEncoded: false)
      if path.utf8.count <= maxPathBytes { return path }
    }
    return "/tmp/ping-\(user).sock"
  }

  /// Whether anything is accepting connections at `path` — a running Ping, as distinct from a
  /// socket file a crashed one left behind.
  public static func isListening(at path: String) -> Bool {
    guard let fd = try? connect(to: path) else { return false }
    close(fd)
    return true
  }

  /// A blocking stream socket connected to `path`, or `unavailable` when nothing is listening.
  static func connect(to path: String) throws -> Int32 {
    var address = try address(path)
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else { throw WatchError.system("socket", code: errno) }
    let result = withUnsafePointer(to: &address) {
      $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
      }
    }
    guard result == 0 else {
      let code = errno
      close(fd)
      if code == ENOENT || code == ECONNREFUSED { throw WatchError.unavailable(path: path) }
      throw WatchError.system("connect", code: code)
    }
    return fd
  }

  static func address(_ path: String) throws -> sockaddr_un {
    let bytes = Array(path.utf8)
    guard bytes.count <= maxPathBytes else { throw WatchError.pathTooLong(path: path) }
    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)
    withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: bytes) }
    return address
  }
}

public enum WatchError: Error, Equatable, CustomStringConvertible {
  /// Nothing is listening: Ping is not running, or is a build without `watch`.
  case unavailable(path: String)
  /// Another Ping is already publishing there, or something that is not our socket sits on the path.
  case inUse(path: String)
  case pathTooLong(path: String)
  /// The app closed a stream it had been answering — it quit or restarted.
  case streamEnded
  case system(String, code: Int32)

  public var description: String {
    switch self {
    case .unavailable(let path):
      return "nothing is listening at \(path) — is Ping running?"
    case .inUse(let path):
      return "\(path) is already in use, by another Ping or by something else"
    case .pathTooLong(let path):
      return "\(path) is longer than a socket path can be (\(WatchSocket.maxPathBytes) bytes)"
    case .streamEnded:
      return "Ping stopped publishing — it quit or restarted"
    case .system(let call, let code):
      return "\(call): \(String(cString: strerror(code)))"
    }
  }
}
