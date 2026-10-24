#include "fiber/browser/pins/tab_sequence.h"

#include <algorithm>
#include <optional>
#include <vector>

#include "base/time/time.h"
#include "chrome/browser/ui/tabs/tab_strip_model.h"
#include "chrome/browser/ui/tabs/tab_strip_user_gesture_details.h"
#include "components/tabs/public/tab_interface.h"
#include "content/public/browser/web_contents.h"
#include "fiber/browser/hooks/tab_strip_selection.h"
#include "fiber/browser/split/tab_split.h"
#include "ui/gfx/range/range.h"

namespace fiber {

namespace {

void Activate(TabStripModel* model, tabs::TabInterface* tab) {
  ActivateBesideKeptTab(
      model, tab,
      TabStripUserGestureDetails(
          TabStripUserGestureDetails::GestureType::kKeyboard));
}

std::vector<tabs::TabInterface*> KeyboardTabs(const TabStripModel& model) {
  tabs::TabInterface* kept = KeptTab(model);
  std::vector<tabs::TabInterface*> tabs;
  for (int i = model.IndexOfFirstNonPinnedTab(); i < model.count(); ++i) {
    if (model.GetTabAtIndex(i) != kept) {
      tabs.push_back(model.GetTabAtIndex(i));
    }
  }
  return tabs;
}

}  // namespace

void SelectAdjacentTab(TabStripModel* model, int offset) {
  const std::vector<tabs::TabInterface*> tabs = KeyboardTabs(*model);
  const int count = static_cast<int>(tabs.size());
  if (count == 0) {
    return;
  }
  tabs::TabInterface* active = model->GetActiveTab();
  if (active && active == KeptTab(*model)) {
    active = model->GetTabAtIndex(model->GetIndexOfTab(active) - 1);
  }
  const auto position = std::ranges::find(tabs, active);
  const int from = position != tabs.end()
                       ? static_cast<int>(position - tabs.begin())
                       : (offset > 0 ? -1 : count);
  Activate(model, tabs[((from + offset) % count + count) % count]);
}

void SelectTabAt(TabStripModel* model, int index) {
  const std::vector<tabs::TabInterface*> tabs = KeyboardTabs(*model);
  const int count = static_cast<int>(tabs.size());
  if (index < 0) {
    index = count - 1;
  }
  if (index >= 0 && index < count) {
    Activate(model, tabs[index]);
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
