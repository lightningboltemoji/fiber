import ApplicationServices
import Foundation

/// An element of an app's accessibility tree. Frames are global, top-left
/// origin points, as CGEvent and CGWindow use.
struct AXElement {
  let ref: AXUIElement

  static func application(_ pid: pid_t) -> AXElement {
    let app = AXUIElementCreateApplication(pid)
    AXUIElementSetMessagingTimeout(app, 2)
    return AXElement(ref: app)
  }

  func value(_ attribute: String) -> AnyObject? {
    var value: AnyObject?
    let error = AXUIElementCopyAttributeValue(ref, attribute as CFString, &value)
    return error == .success ? value : nil
  }

  func string(_ attribute: String) -> String? {
    value(attribute) as? String
  }

  @discardableResult
  func set(_ attribute: String, _ value: CFTypeRef) -> AXError {
    AXUIElementSetAttributeValue(ref, attribute as CFString, value)
  }

  var role: String? { string(kAXRoleAttribute) }
  var subrole: String? { string(kAXSubroleAttribute) }
  var title: String? { string(kAXTitleAttribute) }

  var children: [AXElement] {
    (value(kAXChildrenAttribute) as? [AXUIElement] ?? []).map(AXElement.init)
  }

  var frame: CGRect? {
    guard let position = value(kAXPositionAttribute), let size = value(kAXSizeAttribute) else {
      return nil
    }
    var origin = CGPoint.zero
    var extent = CGSize.zero
    AXValueGetValue(position as! AXValue, .cgPoint, &origin)
    AXValueGetValue(size as! AXValue, .cgSize, &extent)
    return CGRect(origin: origin, size: extent)
  }

  /// Moves before resizing, since AppKit fits the new size to the display
  /// from where the window is.
  func setFrame(_ frame: CGRect) {
    var origin = frame.origin
    var size = frame.size
    set(kAXPositionAttribute, AXValueCreate(.cgPoint, &origin)!)
    set(kAXSizeAttribute, AXValueCreate(.cgSize, &size)!)
    set(kAXPositionAttribute, AXValueCreate(.cgPoint, &origin)!)
  }

  /// Whether any of the labels people see on it contains `label`.
  func matches(_ label: String) -> Bool {
    [kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute, kAXHelpAttribute]
      .compactMap { string($0) }
      .contains { $0.localizedCaseInsensitiveContains(label) }
  }

  /// The elements under it with `role` and `label`, depth first, in the
  /// order they're drawn. Pages' contents aren't searched: tapes find those
  /// by CSS selector.
  func find(role: String, label: String?, limit: Int = .max) -> [AXElement] {
    var found: [AXElement] = []
    func visit(_ element: AXElement, depth: Int) {
      guard depth < 40, found.count < limit else {
        return
      }
      let elementRole = element.role
      if elementRole == role, label.map(element.matches) ?? true {
        found.append(element)
      }
      guard elementRole != "AXWebArea" else {
        return
      }
      for child in element.children {
        visit(child, depth: depth + 1)
      }
    }
    visit(self, depth: 0)
    return found
  }

  /// The tree under it, a line per element, for writing tapes against.
  func dump(depth: Int = 0, into out: inout String) {
    let labels = [kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute]
      .compactMap { string($0) }.filter { !$0.isEmpty }
      .map { "\"\($0.prefix(48))\"" }
    let frame = self.frame.map { " (\(Int($0.minX)),\(Int($0.minY)) \(Int($0.width))×\(Int($0.height)))" } ?? ""
    let role = self.role
    out += String(repeating: "  ", count: depth) + (role ?? "?") + " " + labels.joined(separator: " ") + frame + "\n"
    for child in children where depth < 30 && role != "AXWebArea" {
      child.dump(depth: depth + 1, into: &out)
    }
  }
}
