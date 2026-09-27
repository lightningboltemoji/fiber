#include "fiber/renderer/hooks/page_scrollbar.h"

#include <cmath>

#include "ui/gfx/geometry/insets.h"

namespace fiber {

gfx::Rect PageScrollbarRect(const gfx::Rect& rect, float scale_from_dip) {
  // How far in from the window's right edge: past the tab picker's bump,
  // which shows half its width (TabPickerModel.bumpWidth, in
  // ui/Sources/FiberUI/TabPicker.swift) and opens the picker under the
  // pointer.
  constexpr float kEdgeInset = 8;
  // How far short of the window's top and bottom.
  constexpr float kEndInset = 8;
  gfx::Rect page_rect = rect;
  page_rect.Offset(-std::round(kEdgeInset * scale_from_dip), 0);
  page_rect.Inset(gfx::Insets::VH(std::round(kEndInset * scale_from_dip), 0));
  return page_rect;
}

}  // namespace fiber
