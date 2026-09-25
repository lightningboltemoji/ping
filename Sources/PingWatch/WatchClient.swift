//
//  WatchClient.swift
//  PingWatch
//
//  The CLI's half. Blocking on purpose: `ping-dot-app watch` is a process with nothing else to do,
//  and a Dock nobody touches is silent for hours, so there is no receive timeout either.
//

import Darwin
import Foundation

public enum WatchClient {

  /// Hands `line` every reading the app publishes, the current one first, without its `\n`.
  /// Never returns: Ping quitting is `streamEnded`, and a caller stops early by throwing.
  public static func watch(
    path: String = WatchSocket.path(),
    _ line: (Data) throws -> Void
  ) throws -> Never {
    let fd = try WatchSocket.connect(to: path)
    defer { close(fd) }

    var pending = Data()
    var chunk = [UInt8](repeating: 0, count: 16 * 1024)
    while true {
      let received = chunk.withUnsafeMutableBytes { read(fd, $0.baseAddress, $0.count) }
      if received > 0 {
        pending.append(contentsOf: chunk[0..<received])
        while let newline = pending.firstIndex(of: 0x0A) {
          let whole = pending[pending.startIndex..<newline]
          pending = Data(pending[pending.index(after: newline)...])
          try line(Data(whole))
        }
        continue
      }
      if received == 0 { throw WatchError.streamEnded }
      if errno == EINTR { continue }
      throw WatchError.system("read", code: errno)
    }
  }
}
