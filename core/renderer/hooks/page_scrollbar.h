#ifndef FIBER_RENDERER_HOOKS_PAGE_SCROLLBAR_H_
#define FIBER_RENDERER_HOOKS_PAGE_SCROLLBAR_H_

#include "ui/gfx/geometry/rect.h"

namespace fiber {

// Where the page's scrollbar goes, given `rect`, where Chrome puts it: the
// main frame's overlay vertical scrollbar, against the window's right edge.
// Fiber moves it in, clear of the tab picker, and short of the window's
// corners. `scale_from_dip` is the scrollbar's pixels to a point. Called from
// PaintLayerScrollableArea::RectForVerticalScrollbar() (see patches/chromium/
// third_party-blink-renderer-core-paint-paint_layer_scrollable_area.cc.patch).
gfx::Rect PageScrollbarRect(const gfx::Rect& rect, float scale_from_dip);

}  // namespace fiber

#endif  // FIBER_RENDERER_HOOKS_PAGE_SCROLLBAR_H_
