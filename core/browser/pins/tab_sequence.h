#ifndef FIBER_BROWSER_PINS_TAB_SEQUENCE_H_
#define FIBER_BROWSER_PINS_TAB_SEQUENCE_H_

class TabStripModel;

namespace fiber {

// The tabs the keyboard goes through, and that take over from a closed tab,
// are a window's tabs that aren't pins', in the tab strip's order (after the
// pins' tabs). The user goes to a pin and leaves it, never passes through it.

// Activates the tab `offset` places from the active one, round from the last
// to the first. From a pin's tab, the first is a place on, the last a place
// back.
void SelectAdjacentTab(TabStripModel* model, int offset);

// Activates the tab at `index` from the first, or the last for -1.
void SelectTabAt(TabStripModel* model, int index);

}  // namespace fiber

#endif  // FIBER_BROWSER_PINS_TAB_SEQUENCE_H_
