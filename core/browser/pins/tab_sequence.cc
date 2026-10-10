#include "fiber/browser/pins/tab_sequence.h"

#include <optional>

#include "base/time/time.h"
#include "chrome/browser/ui/tabs/tab_strip_model.h"
#include "chrome/browser/ui/tabs/tab_strip_user_gesture_details.h"
#include "content/public/browser/web_contents.h"
#include "fiber/browser/hooks/tab_strip_selection.h"
#include "ui/gfx/range/range.h"

namespace fiber {

namespace {

void Activate(TabStripModel* model, int index) {
  model->ActivateTabAt(
      index, TabStripUserGestureDetails(
                 TabStripUserGestureDetails::GestureType::kKeyboard));
}

}  // namespace

void SelectAdjacentTab(TabStripModel* model, int offset) {
  const int first = model->IndexOfFirstNonPinnedTab();
  const int count = model->count() - first;
  if (count == 0) {
    return;
  }
  const int active = model->active_index();
  const int from =
      active >= first ? active - first : (offset > 0 ? -1 : count);
  Activate(model, first + ((from + offset) % count + count) % count);
}

void SelectTabAt(TabStripModel* model, int index) {
  const int first = model->IndexOfFirstNonPinnedTab();
  const int count = model->count() - first;
  if (index < 0) {
    index = count - 1;
  }
  if (index >= 0 && index < count) {
    Activate(model, first + index);
  }
}

std::optional<int> TabToActivateAfterClosing(const TabStripModel& model,
                                             const gfx::Range& closing) {
  const int first = model.IndexOfFirstNonPinnedTab();
  const int start = static_cast<int>(closing.start());
  const int end = static_cast<int>(closing.end());
  if (start < first) {
    // A pin's tab: back to the tab used last.
    std::optional<int> last_used;
    base::Time last_used_time;
    for (int i = first; i < model.count(); ++i) {
      const base::Time time = model.GetWebContentsAt(i)->GetLastActiveTime();
      if ((i < start || i >= end) && (!last_used || time > last_used_time)) {
        last_used = i;
        last_used_time = time;
      }
    }
    return last_used;
  }
  // The tab after it, or before it if it was last, but not a pin's. With none
  // left, the window opens a New Tab page in its place (see
  // FiberBrowserWindow::WillCloseTabs()).
  if (end < model.count()) {
    return end;
  }
  if (start > first) {
    return start - 1;
  }
  return std::nullopt;
}

}  // namespace fiber
