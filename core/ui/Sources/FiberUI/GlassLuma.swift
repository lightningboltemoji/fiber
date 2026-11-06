import Foundation
import ObjectiveC

/// Keeps glass in the appearance it's given. On macOS 26, each piece flips
/// between light and dark by the luma behind it, so neighbors disagree over a
/// page. No public API stops that; all glass hears the luma through SDFLayer.
enum GlassLuma {
  static let ignored: Void = {
    guard #unavailable(macOS 27),
      let layer = NSClassFromString("SwiftUI.SDFLayer"),
      let method = class_getInstanceMethod(
        layer, NSSelectorFromString("backdropLayer:didChangeLuma:"))
    else { return }
    let ignore: @convention(block) (AnyObject, AnyObject, Double) -> Void = {
      _, _, _ in
    }
    method_setImplementation(method, imp_implementationWithBlock(ignore))
  }()
}
