#include "fiber/renderer/hooks/page_scrollbar.h"

#include <cmath>

#include "ui/gfx/geometry/insets.h"

namespace fiber {

gfx::Rect PageScrollbarRect(const gfx::Rect& rect, float scale_from_dip) {
  // How far in from the page's right edge, for a little air between the
  // thumb and the gutter.
  constexpr float kEdgeInset = 4;
  // How far short of the page's top and bottom, clear of its rounded corners
  // (PageGutter.cornerRadius, in ui/Sources/FiberUI/PageGutter.swift): the
  // thumb, a few points in from the page's edge, meets the corners' curve
  // about this far from the ends.
  constexpr float kEndInset = 8;
  gfx::Rect page_rect = rect;
  page_rect.Offset(-std::round(kEdgeInset * scale_from_dip), 0);
  page_rect.Inset(gfx::Insets::VH(std::round(kEndInset * scale_from_dip), 0));
  return page_rect;
}

}  // namespace fiber
