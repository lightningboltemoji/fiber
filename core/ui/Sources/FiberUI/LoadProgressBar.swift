import AppKit

/// A thin accent-colored bar along the top of the page that tracks load
/// progress, then fills and fades out when loading finishes.
final class LoadProgressBar: NSView {
  private let fill = NSBox()
  private var progress = 0.0
  private var isActive = false

  override init(frame: NSRect) {
    super.init(frame: frame)
    fill.boxType = .custom
    fill.borderWidth = 0
    fill.fillColor = .controlAccentColor
    addSubview(fill)
    wantsLayer = true
    alphaValue = 0
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) is not supported")
  }

  override func hitTest(_ point: NSPoint) -> NSView? {
    nil
  }

  override func resizeSubviews(withOldSize oldSize: NSSize) {
    fill.frame = fillFrame(for: progress)
  }

  func setProgress(_ progress: Double) {
    if !isActive {
      // Start empty rather than shrinking from the last load's full bar.
      isActive = true
      fill.frame = fillFrame(for: 0)
      NSAnimationContext.runAnimationGroup { context in
        context.duration = 0
        animator().alphaValue = 1
      }
    }
    self.progress = progress
    NSAnimationContext.runAnimationGroup { context in
      context.duration = 0.2
      fill.animator().frame = fillFrame(for: progress)
    }
  }

  func finish() {
    if !isActive {
      return
    }
    isActive = false
    progress = 1
    NSAnimationContext.runAnimationGroup { context in
      context.duration = 0.15
      fill.animator().frame = fillFrame(for: 1)
    } completionHandler: {
      MainActor.assumeIsolated {
        if self.isActive {
          return  // Another load started meanwhile.
        }
        NSAnimationContext.runAnimationGroup { context in
          context.duration = 0.3
          self.animator().alphaValue = 0
        }
      }
    }
  }

  private func fillFrame(for progress: Double) -> NSRect {
    NSRect(x: 0, y: 0, width: bounds.width * progress, height: bounds.height)
  }
}
