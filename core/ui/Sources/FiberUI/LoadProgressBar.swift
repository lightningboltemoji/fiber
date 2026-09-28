import AppKit

/// A thin bar along the top of the page for load progress. It shows only once
/// a load has taken `revealDelay`, so quick ones (the New Tab page, most
/// pages) never show it.
final class LoadProgressBar: NSView {
  private static let revealDelay: Duration = .milliseconds(500)

  private enum State {
    case idle
    /// Loading, but not yet for `revealDelay`.
    case pending(reveal: Task<Void, Never>)
    case shown
  }

  private let fill = NSBox()
  private var progress = 0.0
  private var state = State.idle

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
    self.progress = progress
    switch state {
    case .idle:
      let reveal = Task { [weak self] in
        try? await Task.sleep(for: Self.revealDelay)
        if !Task.isCancelled {
          self?.reveal()
        }
      }
      state = .pending(reveal: reveal)
    case .pending:
      break
    case .shown:
      animateFill()
    }
  }

  func finish() {
    switch state {
    case .idle:
      return
    case .pending(let reveal):
      reveal.cancel()
      state = .idle
      return
    case .shown:
      break
    }
    state = .idle
    progress = 1
    NSAnimationContext.runAnimationGroup { context in
      context.duration = 0.15
      fill.animator().frame = fillFrame(for: 1)
    } completionHandler: {
      MainActor.assumeIsolated {
        guard case .idle = self.state else {
          return  // Another load started meanwhile.
        }
        NSAnimationContext.runAnimationGroup { context in
          context.duration = 0.3
          self.animator().alphaValue = 0
        }
      }
    }
  }

  private func reveal() {
    state = .shown
    // Start empty rather than shrinking from the last load's full bar.
    fill.frame = fillFrame(for: 0)
    NSAnimationContext.runAnimationGroup { context in
      context.duration = 0
      animator().alphaValue = 1
    }
    animateFill()
  }

  private func animateFill() {
    NSAnimationContext.runAnimationGroup { context in
      context.duration = 0.2
      fill.animator().frame = fillFrame(for: progress)
    }
  }

  private func fillFrame(for progress: Double) -> NSRect {
    NSRect(x: 0, y: 0, width: bounds.width * progress, height: bounds.height)
  }
}
