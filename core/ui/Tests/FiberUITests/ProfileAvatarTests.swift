import AppKit
import Testing

@testable import FiberUI

struct ProfileAvatarTests {
  @Test func everySymbolExists() {
    for name in ProfileAvatar.symbolNames {
      #expect(
        NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil,
        "\(name)")
    }
  }

  // Chrome offers 27 to 55, and each should look different.
  @Test func choicesAreDistinct() {
    let symbols = ProfileAvatar.choices.map { ProfileAvatar(index: $0).symbolName }
    #expect(Set(symbols).count == symbols.count)
  }

  @MainActor @Test func drawsPNG() {
    let png = ProfileAvatar(index: 30).png(pixelSize: 96)
    let image = NSBitmapImageRep(data: png)
    #expect(image?.pixelsWide == 96)
  }
}
