//
// From: https://christiantietze.de/posts/2024/03/ship-custom-fonts-within-a-swift-package/
//

import SwiftUI

public enum FontLoader {
  public static func load() {
    let fontURLs = ["Chango-Regular"].compactMap {
      PingResources.bundle.url(forResource: $0, withExtension: "ttf")
    }

    CTFontManagerRegisterFontURLs(fontURLs as CFArray, .process, true) { errors, done in
      let errors = errors as! [CFError]
      guard errors.isEmpty else {
        preconditionFailure(
          "Registering font failed: \(errors.map(\.localizedDescription))")
      }
      return true
    }
  }
}
