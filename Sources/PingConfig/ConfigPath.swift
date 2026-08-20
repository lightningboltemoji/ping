//
//  ConfigPath.swift
//  PingConfig
//

import Foundation

public enum ConfigPath {
  /// `$PING_CONFIG` if it is set, else `~/.config/ping/ping.toml`.
  public static var url: URL {
    if let override = ProcessInfo.processInfo.environment["PING_CONFIG"], !override.isEmpty {
      return URL(fileURLWithPath: (override as NSString).expandingTildeInPath)
    }
    return defaultURL
  }

  public static var defaultURL: URL {
    FileManager.default.homeDirectoryForCurrentUser
      .appending(path: ".config/ping/ping.toml")
  }
}
