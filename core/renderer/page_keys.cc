#include "fiber/renderer/page_keys.h"

#include "third_party/blink/public/common/input/web_keyboard_event.h"
#include "third_party/blink/renderer/core/dom/document.h"
#include "third_party/blink/renderer/core/dom/flat_tree_traversal.h"
#include "third_party/blink/renderer/core/dom/node.h"
#include "third_party/blink/renderer/core/event_type_names.h"
#include "third_party/blink/renderer/core/frame/local_dom_window.h"
#include "third_party/blink/renderer/platform/keyboard_codes.h"

namespace fiber {

bool IsPageKey(const blink::WebKeyboardEvent& event, blink::Node& target) {
  if (event.windows_key_code != blink::VKEY_ESCAPE) {
    return false;
  }
  const auto& keydown = blink::event_type_names::kKeydown;
  for (blink::Node* node = &target; node;
       node = blink::FlatTreeTraversal::Parent(*node)) {
    if (node->HasEventListeners(keydown)) {
      return true;
    }
  }
  blink::Document& document = target.GetDocument();
  blink::LocalDOMWindow* window = document.domWindow();
  return document.HasEventListeners(keydown) ||
         (window && window->HasEventListeners(keydown));
}

}  // namespace fiber
