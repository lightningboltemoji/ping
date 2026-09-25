//
//  WatchServer.swift
//  PingWatch
//
//  The app's half. Every connection is a watcher: it is sent the current reading on arrival and
//  each new one after. Nothing a watcher writes is read — the socket speaks and never listens.
//

import Darwin
import Foundation

/// Publishes one line at a time to every watcher. All of its state lives on `queue`, and
/// `publish` returns at once, so a slow watcher never holds up the caller.
public final class WatchServer: @unchecked Sendable {

  public let path: String
  private let queue = DispatchQueue(label: "Ping.watch")
  private var acceptor: DispatchSourceRead?
  private var watchers: [ObjectIdentifier: Watcher] = [:]
  /// What a new watcher is sent first.
  private var latest: Data?
  private var bound = false

  public init(path: String = WatchSocket.path()) {
    self.path = path
  }

  /// Binds and listens. Refuses a path a live Ping holds, and anything there that is not a
  /// socket this user owns; a socket file a crashed Ping left behind is replaced.
  public func start() throws {
    try queue.sync { try listen() }
  }

  /// `line` is one whole reading, ending in `\n`.
  public func publish(_ line: Data) {
    queue.async { [self] in
      latest = line
      for watcher in watchers.values { watcher.send(line) }
    }
  }

  public func stop() {
    queue.sync {
      acceptor?.cancel()
      acceptor = nil
      for watcher in watchers.values { watcher.drop() }
      if bound {
        unlink(path)
        bound = false
      }
    }
  }

  public var watcherCount: Int { queue.sync { watchers.count } }

  // MARK: - Listening

  private func listen() throws {
    var address = try WatchSocket.address(path)
    if occupied() { throw WatchError.inUse(path: path) }
    unlink(path)

    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else { throw WatchError.system("socket", code: errno) }
    let result = withUnsafePointer(to: &address) {
      $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
      }
    }
    guard result == 0 else {
      let code = errno
      close(fd)
      throw WatchError.system("bind", code: code)
    }
    bound = true
    chmod(path, 0o600)
    guard Darwin.listen(fd, 16) == 0 else {
      let code = errno
      close(fd)
      unlink(path)
      bound = false
      throw WatchError.system("listen", code: code)
    }
    Self.makeNonBlocking(fd)

    let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
    source.setEventHandler { [weak self] in self?.accept(from: fd) }
    source.setCancelHandler { close(fd) }
    source.resume()
    acceptor = source
  }

  /// Something that must not be unlinked: a live Ping, or anything but a socket this user owns.
  private func occupied() -> Bool {
    var info = stat()
    guard lstat(path, &info) == 0 else { return false }
    if info.st_mode & S_IFMT != S_IFSOCK || info.st_uid != getuid() { return true }
    return WatchSocket.isListening(at: path)
  }

  private func accept(from listener: Int32) {
    while true {
      let fd = Darwin.accept(listener, nil, nil)
      guard fd >= 0 else {
        if errno == EINTR || errno == ECONNABORTED { continue }
        return
      }
      Self.makeNonBlocking(fd)
      var on: Int32 = 1
      setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
      let watcher = Watcher(fd: fd, queue: queue) { [weak self] gone in
        self?.watchers[ObjectIdentifier(gone)] = nil
      }
      watchers[ObjectIdentifier(watcher)] = watcher
      if let latest { watcher.send(latest) }
    }
  }

  private static func makeNonBlocking(_ fd: Int32) {
    _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
  }
}

/// One connection, touched only on the server's queue. Latest wins: a line already begun is
/// finished, since a torn line is a broken reading, but one still waiting is replaced by a newer one.
private final class Watcher {

  /// Two sources share one descriptor, so whichever cancel handler runs last closes it.
  private final class Descriptor {
    let fd: Int32
    var holds = 2
    init(_ fd: Int32) { self.fd = fd }
  }

  private let fd: Int32
  private let reader: DispatchSourceRead
  private let writer: DispatchSourceWrite
  private let onDrop: (Watcher) -> Void
  /// Whether the write source is resumed, which it is only while a write would block.
  private var writing = false
  private var dropped = false
  private var sending = Data()
  private var next: Data?

  init(fd: Int32, queue: DispatchQueue, onDrop: @escaping (Watcher) -> Void) {
    self.fd = fd
    self.onDrop = onDrop
    reader = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
    writer = DispatchSource.makeWriteSource(fileDescriptor: fd, queue: queue)

    let descriptor = Descriptor(fd)
    let release = {
      descriptor.holds -= 1
      if descriptor.holds == 0 { close(descriptor.fd) }
    }
    reader.setCancelHandler(handler: release)
    writer.setCancelHandler(handler: release)
    reader.setEventHandler { [weak self] in self?.readable() }
    writer.setEventHandler { [weak self] in self?.flush() }
    reader.resume()
  }

  func send(_ line: Data) {
    guard !dropped else { return }
    if sending.isEmpty { sending = line } else { next = line }
    if !writing { flush() }
  }

  func drop() {
    guard !dropped else { return }
    dropped = true
    // A suspended source never runs its cancel handler.
    if !writing { writer.resume() }
    writer.cancel()
    reader.cancel()
    onDrop(self)
  }

  /// A watcher has nothing to say, so a read can only be it leaving.
  private func readable() {
    var scratch = [UInt8](repeating: 0, count: 512)
    let count = scratch.withUnsafeMutableBytes { read(fd, $0.baseAddress, $0.count) }
    if count > 0 { return }
    if count < 0 && (errno == EAGAIN || errno == EINTR) { return }
    drop()
  }

  private func flush() {
    while !dropped {
      if sending.isEmpty {
        guard let line = next else { break }
        sending = line
        next = nil
      }
      let written = sending.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
      if written > 0 {
        sending = sending.dropFirst(written)
        continue
      }
      if written < 0 && errno == EINTR { continue }
      if written < 0 && errno == EAGAIN {
        arm(true)
        return
      }
      drop()
      return
    }
    arm(false)
  }

  private func arm(_ on: Bool) {
    guard on != writing, !dropped else { return }
    writing = on
    if on { writer.resume() } else { writer.suspend() }
  }
}
