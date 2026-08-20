//
//  main.swift
//  ping-dot-app
//
//  `validate [path]` — exit 0, or exit 1 with `path:line: message` on stderr. Enough to keep
//  a config honest in dotfiles CI.
//
//  `explain [key]` — the settings table, printed. A few lines over `ConfigSchema` now that it
//  is enumerable, and the third consumer that keeps the table paying for itself:
//  the window lays itself out from the same list this prints and the writer unsets from.
//
//  The binary ships as `ping-dot-app` because `ping` is /sbin/ping, but nothing here assumes
//  that: every line it prints about itself is built from `name`, so a symlink called `ping`,
//  or anything else, describes itself and not some other command.
//

import Foundation
import PingConfig

/// What this binary was invoked as, which is what it should call itself. `ping-dot-app` when
/// installed, `ping` under the symlink most people will make, and the right answer either way.
private let name =
  (CommandLine.arguments.first.map { ($0 as NSString).lastPathComponent })
  ?? "ping-dot-app"

private func fail(_ message: String) -> Never {
  FileHandle.standardError.write(Data((message + "\n").utf8))
  exit(1)
}

private func usage() -> Never {
  print(
    """
    usage: \(name) validate [path]
           \(String(repeating: " ", count: name.count)) explain [key]

      validate  Reads path (default $PING_CONFIG, else ~/.config/ping/ping.toml) and reports
                the first problem it finds. A missing file is valid: it means every default.
      explain   Prints what a key means, what it may be set to, and what it is when the file
                says nothing. With no key, prints every setting.
    """)
  exit(0)
}

/// One setting, as `explain` prints it: what it is called, what it does, what it may be, and what
/// it is when the file is silent.
private func explain(_ setting: Setting) {
  print("\(setting.key)")
  print("    \(setting.help)")
  if let legend = setting.legend {
    print("    \(legend)")
  }
  print("    default: \(setting.defaultValue.spelled)")
}

let arguments = Array(CommandLine.arguments.dropFirst())

switch arguments.first {
case "validate":
  let url =
    arguments.count > 1
    ? URL(fileURLWithPath: (arguments[1] as NSString).expandingTildeInPath)
    : ConfigPath.url
  let display = url.path

  guard FileManager.default.fileExists(atPath: url.path) else {
    print("\(display): not found — every default applies")
    exit(0)
  }

  let text: String
  do {
    text = try String(contentsOf: url, encoding: .utf8)
  } catch {
    fail("\(display): \(error.localizedDescription)")
  }

  do {
    let parsed = try Config.parse(text)
    for diagnostic in parsed.diagnostics {
      FileHandle.standardError.write(
        Data("\(display):\(diagnostic.line): \(diagnostic.message)\n".utf8))
    }
    let apps = parsed.config.apps.count
    print("\(display): ok (\(apps) app\(apps == 1 ? "" : "s"))")
  } catch let error as ConfigSyntaxError {
    fail("\(display):\(error.line): \(error.message)")
  } catch {
    fail("\(display): \(error)")
  }

case "explain":
  let settings: [Setting]
  if arguments.count > 1 {
    let wanted = TOMLKey(arguments[1].split(separator: ".").map(String.init))
    // A whole table is as good an argument as one key — `ping explain glow` is the question
    // somebody actually has.
    settings = Setting.all.filter { $0.key == wanted || $0.table == wanted }
    guard !settings.isEmpty else {
      fail("\(name): no setting called '\(arguments[1])'")
    }
  } else {
    settings = Setting.all
  }
  for (index, setting) in settings.enumerated() {
    if index > 0 { print("") }
    explain(setting)
  }

case "-h", "--help", "help", .none:
  usage()

default:
  fail(
    "\(name): unknown command '\(arguments[0])'\n"
      + "usage: \(name) validate [path] | \(name) explain [key]")
}
