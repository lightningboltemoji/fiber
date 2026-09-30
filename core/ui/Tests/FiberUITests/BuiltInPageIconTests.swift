import AppKit
import Testing

@testable import FiberUI

struct BuiltInPageIconTests {
  @Test func everySymbolExists() {
    let names =
      Array(BuiltInPageIcon.symbolNames.values)
      + [BuiltInPageIcon.otherSymbolName]
    for name in names {
      #expect(
        NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil,
        "\(name)")
    }
  }
}
