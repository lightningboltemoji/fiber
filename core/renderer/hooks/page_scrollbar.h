#ifndef FIBER_RENDERER_HOOKS_PAGE_SCROLLBAR_H_
#define FIBER_RENDERER_HOOKS_PAGE_SCROLLBAR_H_

#include "ui/gfx/geometry/rect.h"

namespace fiber {

// Where the main frame's overlay vertical scrollbar goes, given `rect`, where
// Chrome puts it: in from the window's right edge, clear of the tab picker, and
// short of the page's rounded corners. Called from
// PaintLayerScrollableArea::RectForVerticalScrollbar().
gfx::Rect PageScrollbarRect(const gfx::Rect& rect, float scale_from_dip);

}  // namespace fiber

#endif  // FIBER_RENDERER_HOOKS_PAGE_SCROLLBAR_H_
