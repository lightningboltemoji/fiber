import AppKit
import FiberBridge
import SwiftUI

@objc @implementation extension FiberShelfState {
  let shelfID: String
  let name: String
  let pages: [FiberPinState]

  @objc(initWithID:name:pages:)
  init(id shelfID: String, name: String, pages: [FiberPinState]) {
    self.shelfID = shelfID
    self.name = name
    self.pages = pages
    super.init()
  }
}

/// The profile's shelves, from the browser, which the tab overlay lists.
@MainActor
final class WindowShelves: NSObject, FiberShelves {
  var actions: (any FiberShelvesActions)?
  var onChange: ([FiberShelfState]) -> Void = { _ in }

  func setShelves(_ shelves: [FiberShelfState]) {
    onChange(shelves)
  }
}

/// What the tab overlay's list shows: the window's own tabs, or a shelf's
/// pages.
enum ShelfSegment: Hashable {
  case home
  case shelf(String)
}

/// A row of the tab overlay's list being dragged onto the shelf bar.
struct TabDrag: Equatable {
  let rowID: TabListRow.ID
  /// Where the pointer is, in the overlay.
  var point: CGPoint
  /// Where it would go if dropped now: a segment other than the list's.
  var target: ShelfSegment?
}

/// A row being dragged to the shelf bar, lifted off the list as a capsule of
/// glass under the pointer. Over a segment it can drop on, it draws in to a
/// bead of its icon above the pointer, clear of the segment's name.
struct DraggedRow: View {
  static let width: CGFloat = 240
  static let beadDiameter = PinGridLayout.diameter
  /// From the pointer to the bead's center.
  static let beadRise: CGFloat = 36
  /// From the capsule's left end to the pointer.
  static let grip: CGFloat = 24

  let row: TabListRow
  let isOverTarget: Bool

  /// Its center, for the pointer at `point`.
  static func center(for point: CGPoint, isOverTarget: Bool) -> CGPoint {
    isOverTarget
      ? CGPoint(x: point.x, y: point.y - beadRise)
      : CGPoint(x: point.x + width / 2 - grip, y: point.y)
  }

  var body: some View {
    let height = isOverTarget ? Self.beadDiameter : GlassCapsule.height
    let width = isOverTarget ? Self.beadDiameter : Self.width
    HStack(spacing: 8) {
      Group {
        if let favicon = row.favicon {
          Image(nsImage: favicon)
            .resizable()
            .interpolation(.high)
        } else {
          Image(systemName: "globe")
            .foregroundStyle(.secondary)
        }
      }
      .frame(width: 16, height: 16)
      if !isOverTarget {
        Text(row.title.isEmpty ? "Untitled" : row.title)
          .font(.system(size: 13, weight: .medium))
          .lineLimit(1)
          .truncationMode(.tail)
          .transition(.opacity)
      }
    }
    .padding(.horizontal, isOverTarget ? 10 : 14)
    .frame(width: width, height: height, alignment: .leading)
    .background {
      RimmedGlass(cornerRadius: height / 2, rimWidth: GlassCapsule.rimWidth)
    }
    .shadow(color: .black.opacity(0.3), radius: 14, y: 6)
  }
}
