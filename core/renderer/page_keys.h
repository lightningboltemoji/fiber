#ifndef FIBER_RENDERER_PAGE_KEYS_H_
#define FIBER_RENDERER_PAGE_KEYS_H_

namespace blink {
class Node;
class WebKeyboardEvent;
}  // namespace blink

namespace fiber {

// Whether a key down is the page's even if no listener cancels it: Escape
// with a keydown listener on its way to `target`. The browser closes a peek on
// Escape a page leaves (fiber/browser/peek/tab_peek.h), and a page's own use
// of it, closing a menu say, comes first. Called by
// KeyboardEventManager::KeyEvent() before the page's listeners run, since one
// may remove itself.
bool IsPageKey(const blink::WebKeyboardEvent& event, blink::Node& target);

}  // namespace fiber

#endif  // FIBER_RENDERER_PAGE_KEYS_H_
