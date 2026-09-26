import AppKit
import ObjectiveC

/// Where AppKit puts a window's traffic lights, which it has no public API to
/// move.
///
/// Like Chrome's BrowserWindowFrame
/// (components/remote_cocoa/app_shim/browser_native_widget_window_mac.mm),
/// this subclasses the window's frame view, AppKit's private NSThemeFrame, and
/// overrides the private methods it lays them out with: the traffic lights sit
/// `inset.width` from the window's left edge, centered in a title bar
/// `titlebarHeight` tall. Fullscreen keeps AppKit's layout, where the title bar
/// slides down with the menu bar.
///
/// A window uses it by returning `frameViewClass(base:)` from its (private)
/// `+frameViewClassForStyleMask:`.
@MainActor
enum WindowFrame {
  struct Layout {
    var buttonsInset: CGFloat
    var titlebarHeight: CGFloat
  }

  private static var subclasses: [ObjectIdentifier: AnyClass] = [:]

  /// A subclass of `base` (the frame view class AppKit chose) that lays the
  /// traffic lights out as `layout` says.
  static func frameViewClass(base: AnyClass, layout: Layout) -> AnyClass {
    if let subclass = subclasses[ObjectIdentifier(base)] {
      return subclass
    }
    let name = "Fiber\(NSStringFromClass(base))"
    guard let subclass = objc_allocateClassPair(base, name, 0) else {
      return base
    }
    override(
      "_minXTitlebarWidgetInset", in: subclass, base: base,
      value: layout.buttonsInset)
    override(
      "_titlebarHeight", in: subclass, base: base,
      value: layout.titlebarHeight)
    let center: @convention(block) (NSView) -> Bool = { _ in true }
    class_addMethod(
      subclass, NSSelectorFromString("_shouldCenterTrafficLights"),
      imp_implementationWithBlock(center), "B@:")
    objc_registerClassPair(subclass)
    subclasses[ObjectIdentifier(base)] = subclass
    return subclass
  }

  /// Makes `subclass` answer `value` to a CGFloat getter, except while its
  /// window is fullscreen, when it answers what `base` does.
  private static func override(
    _ name: String, in subclass: AnyClass, base: AnyClass, value: CGFloat
  ) {
    let selector = NSSelectorFromString(name)
    guard let baseMethod = class_getInstanceMethod(base, selector) else {
      return
    }
    typealias Getter = @convention(c) (NSView, Selector) -> CGFloat
    let baseImplementation = unsafeBitCast(
      method_getImplementation(baseMethod), to: Getter.self)
    let getter: @convention(block) (NSView) -> CGFloat = { frameView in
      if frameView.window?.styleMask.contains(.fullScreen) ?? false {
        return baseImplementation(frameView, selector)
      }
      return value
    }
    class_addMethod(
      subclass, selector, imp_implementationWithBlock(getter),
      method_getTypeEncoding(baseMethod))
  }
}
