#ifndef FIBER_BROWSER_HOOKS_TAB_STRIP_SELECTION_H_
#define FIBER_BROWSER_HOOKS_TAB_STRIP_SELECTION_H_

#include <optional>

class TabStripModel;

namespace gfx {
class Range;
}

namespace fiber {

// The tab to activate when the active tab, among the tabs at `closing`,
// closes, ahead of the tabs Chrome finds they opened or were opened from: a
// peek goes back to the tab it's over (see peek/tab_peek.h). Called by
// TabStripModel::DetermineNewSelectedIndex(); nullopt leaves it to Chrome.
std::optional<int> TabToReturnToAfterClosing(const TabStripModel& model,
                                             const gfx::Range& closing);

// The tab to activate when the active tab, among the tabs at `closing`,
// closes, once Chrome has found no tab they opened or were opened from: never
// a pin's tab in place of another tab (see pins/tab_sequence.h). Called by
// TabStripModel::DetermineNewSelectedIndex(); nullopt leaves it to Chrome.
std::optional<int> TabToActivateAfterClosing(const TabStripModel& model,
                                             const gfx::Range& closing);

}  // namespace fiber

#endif  // FIBER_BROWSER_HOOKS_TAB_STRIP_SELECTION_H_
