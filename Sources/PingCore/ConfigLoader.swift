//
//  ConfigLoader.swift
//  PingCore
//
//  The imperative half of the config file: read it, watch it. What a key means, what the
//  diagnostic says and where the file lives are pure and belong to `PingConfig`.
//
//  A change arrives as an `AsyncStream` rather than a callback, because that is how `BadgeMonitor`
//  and `ScreenTopology` already speak and `AppDelegate` is one loop per stream.
//
//  A missing file is not an error — it loads as every default. A broken file changes
//  nothing: falling back to defaults on a syntax error would take every effect off the screen
//  as the side effect of a typo.
//

import Dispatch
import Foundation
import PingConfig

/// Why a config file couldn't be loaded, rendered as the `path:line: message` diagnostic an
/// editor's error parser already knows how to jump to.
public enum ConfigLoadError: Error, Sendable, CustomStringConvertible {
  case unreadable(path: String, reason: String)
  case syntax(path: String, error: ConfigSyntaxError)

  public var description: String {
    switch self {
    case .unreadable(let path, let reason):
      "\(path): \(reason)"
    case .syntax(let path, let error):
      // `ConfigSyntaxError.description` opens with "line N: " because `PingConfig` does not
      // know the file. Here we do, so the line is hoisted into the path prefix.
      "\(path):\(error.line): \(error.message)"
    }
  }
}

/// Reads `~/.config/ping/ping.toml`, and keeps the app in step with it.
@MainActor
public final class ConfigLoader {

  public let url: URL

  /// The last config successfully read — the yardstick for "did this event change anything?".
  private var lastLoaded: ParsedConfig?

  public init(url: URL = ConfigPath.url) {
    self.url = url
  }

  /// Read and parse now. Called once at boot, before there is a loop to send changes to.
  public func load() -> Result<ParsedConfig, ConfigLoadError> {
    let result = read()
    if case .success(let parsed) = result { lastLoaded = parsed }
    return result
  }

  private func read() -> Result<ParsedConfig, ConfigLoadError> {
    guard FileManager.default.fileExists(atPath: url.path) else {
      return .success(ParsedConfig(config: Config()))
    }
    let text: String
    do {
      text = try String(contentsOf: url, encoding: .utf8)
    } catch {
      return .failure(.unreadable(path: url.path, reason: error.localizedDescription))
    }
    do {
      return .success(try Config.parse(text))
    } catch let error as ConfigSyntaxError {
      return .failure(.syntax(path: url.path, error: error))
    } catch {
      return .failure(.unreadable(path: url.path, reason: "\(error)"))
    }
  }

  /// Yields whenever the file changes to something that reads differently.
  ///
  /// **A file that parses to the config already in hand is not reported.** *Any* activity in
  /// the watched directory wakes us, so an editor's swap file would otherwise reload every few
  /// seconds — and a settings window's own save would come back as a change to something it
  /// already knows. That is what makes self-write suppression unnecessary rather than
  /// forgotten. Failures are always reported, because a suppressed repeat would make a
  /// save that *didn't* fix the problem look like one that did.
  ///
  /// A burst of filesystem events collapses into one read `coalesce` later, so one save is one
  /// reload however many events the editor produced writing it.
  public func changes(
    coalesce: Duration = .milliseconds(80)
  ) -> AsyncStream<Result<ParsedConfig, ConfigLoadError>> {
    events(coalesce: coalesce) { loader, yield in
      let result = loader.read()
      if case .success(let parsed) = result {
        let unchanged = parsed == loader.lastLoaded
        loader.lastLoaded = parsed
        if unchanged { return }
      }
      yield(result)
    }
  }

  /// Every change to the file's **text**, not only the ones that read differently.
  ///
  /// What an editing session needs and `changes` deliberately does not give it: a comment somebody
  /// added is not a config change and is still their work, so a draft has to rebase onto it or say
  /// it can't. `nil` when the file is not there — an absent file is an empty one.
  public func textChanges(coalesce: Duration = .milliseconds(80)) -> AsyncStream<String?> {
    events(coalesce: coalesce) { loader, yield in
      yield(try? String(contentsOf: loader.url, encoding: .utf8))
    }
  }

  /// The watch, the coalescing window and the teardown, once — the two streams above differ only
  /// in what they make of the file once something has happened to it.
  private func events<Element: Sendable>(
    coalesce: Duration,
    read: @escaping @MainActor (ConfigLoader, (Element) -> Void) -> Void
  ) -> AsyncStream<Element> {
    AsyncStream { continuation in
      let watcher = ConfigWatcher(watching: url)
      // The flag *is* the coalescing: extra events inside the window are dropped, and the one read
      // that happens sees the file's final state.
      var pending = false
      watcher.start { [weak self] in
        guard !pending else { return }
        pending = true
        Task { @MainActor in
          try? await Task.sleep(for: coalesce)
          pending = false
          guard let self else { return }
          read(self) { continuation.yield($0) }
        }
      }
      continuation.onTermination = { _ in
        Task { @MainActor in watcher.stop() }
      }
    }
  }
}

/// Kernel vnode sources on the config file *and* on its directory, because each half of "the
/// file changed" is invisible to the other watch: an atomic save kills the file watch with the
/// inode it held, and an in-place rewrite never touches the directory entry. So the file source
/// is re-armed *by path* whenever its inode is renamed or unlinked. A file that does not exist
/// yet is fine — the directory watch is what notices it appear.
@MainActor
final class ConfigWatcher {

  private let path: String
  private let directory: String
  private var onChange: (@MainActor () -> Void)?
  private var directorySource: DispatchSourceFileSystemObject?
  private var fileSource: DispatchSourceFileSystemObject?

  init(watching url: URL) {
    self.path = url.path
    self.directory = url.deletingLastPathComponent().path
  }

  /// Whether the containing directory could be opened; `false` means hot reload is off.
  var isWatching: Bool { directorySource != nil }

  func start(_ onChange: @escaping @MainActor () -> Void) {
    guard directorySource == nil else { return }
    self.onChange = onChange
    directorySource = source(for: directory, mask: [.write, .rename, .delete]) { [weak self] _ in
      guard let self else { return }
      // The file may have just been created, or replaced by something we aren't holding.
      if fileSource == nil { armFileSource() }
      self.onChange?()
    }
    armFileSource()
  }

  func stop() {
    directorySource?.cancel()
    directorySource = nil
    fileSource?.cancel()
    fileSource = nil
    onChange = nil
  }

  /// Watch the file at `path` — following the *path*, not the inode, so an atomic save is
  /// survived.
  private func armFileSource() {
    fileSource?.cancel()
    fileSource = source(
      for: path, mask: [.write, .extend, .rename, .delete, .attrib]
    ) { [weak self] events in
      guard let self else { return }
      // A rename or unlink means the inode we hold is no longer what `path` names, so re-open
      // it. A plain write keeps the same file, where re-arming would be churn.
      if events.contains(.rename) || events.contains(.delete) { armFileSource() }
      self.onChange?()
    }
  }

  private func source(
    for path: String, mask: DispatchSource.FileSystemEvent,
    handler: @escaping @MainActor (DispatchSource.FileSystemEvent) -> Void
  ) -> DispatchSourceFileSystemObject? {
    // `O_EVTONLY` doesn't count as a reference that would keep an unmounting volume busy.
    let descriptor = open(path, O_EVTONLY)
    guard descriptor >= 0 else { return nil }
    let source = DispatchSource.makeFileSystemObjectSource(
      fileDescriptor: descriptor, eventMask: mask, queue: .main)
    source.setEventHandler { [weak source] in
      let events = source?.data ?? []
      // The main queue *is* the main actor's executor.
      MainActor.assumeIsolated { handler(events) }
    }
    source.setCancelHandler { close(descriptor) }
    source.resume()
    return source
  }
}
