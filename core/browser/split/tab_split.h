#ifndef FIBER_BROWSER_SPLIT_TAB_SPLIT_H_
#define FIBER_BROWSER_SPLIT_TAB_SPLIT_H_

#include <optional>

#include "base/memory/raw_ptr.h"
#include "components/split_tabs/split_tab_id.h"
#include "components/tabs/public/tab_interface.h"

class TabStripModel;
struct TabStripUserGestureDetails;

namespace fiber {

// A window shows one of Chrome's splits (two adjacent tabs side by side): the
// active tab's, or else its first. Its left tab is the one the user was on
// last, and its right the one they keep there whatever they go to (see
// FiberSplit). A split takes its first tab's pinning, so beside a pin's or
// shelf page's tab, which are Chrome-pinned, the right tab is pinned too,
// though it's no pin (see IsBesidePin()); a pin's is never on the right.

std::optional<split_tabs::SplitTabId> ShownSplit(const TabStripModel& model);

// The shown split's right tab, which the tab overlay keeps apart from the
// list, if there's a split.
tabs::TabInterface* KeptTab(const TabStripModel& model);

// A split Chrome ended without the user asking: its left tab closed, left the
// window or was pinned, or a move took them apart. Its right tab stays.
struct EndedSplit {
  tabs::TabHandle left;
  tabs::TabHandle right;
  double ratio;
  bool was_left_active;
};

// The split the window is to show. Chrome's split is two particular tabs, and
// hides as another becomes active, so the right tab then goes beside that one
// instead (see KeepSplit()), or for an ended split, beside its left again or
// the tab next to it.
struct SplitPlan {
  raw_ptr<tabs::TabInterface> left;
  raw_ptr<tabs::TabInterface> right;
  double ratio;
  // The left tab closed while it was active, and the one taking its place is
  // to be.
  bool activate_left;
};

std::optional<SplitPlan> PlanSplit(const TabStripModel& model,
                                   const std::optional<EndedSplit>& ended);
// Whether Chrome's split, and the active tab, are already as `plan` has them.
bool IsAsPlanned(const TabStripModel& model, const SplitPlan& plan);
// Makes them so.
void KeepSplit(TabStripModel* model, const SplitPlan& plan);

// A tab kept beside a pin whose split is gone (a restore without it, the user
// separating them) goes back among the window's ordinary tabs.
bool HasStrandedTab(const TabStripModel& model);
void ReleaseStrandedTabs(TabStripModel* model);

// Activates `tab`, which takes the left of the shown split if it could be in
// one but isn't.
void ActivateBesideKeptTab(TabStripModel* model,
                           tabs::TabInterface* tab,
                           TabStripUserGestureDetails gesture);

// Puts `right` beside `left`, in place of the shown split, and activates
// `left` if neither is active.
void Split(TabStripModel* model,
           tabs::TabInterface* left,
           tabs::TabInterface* right);
void EndSplit(TabStripModel* model);
void ReverseSplit(TabStripModel* model);
void SetSplitRatio(TabStripModel* model, double ratio);

// Moves `tab`, with its split's other tab, to just before `before`, or after
// the other tabs for null.
void MoveTab(TabStripModel* model,
             tabs::TabInterface* tab,
             tabs::TabInterface* before);

}  // namespace fiber

#endif  // FIBER_BROWSER_SPLIT_TAB_SPLIT_H_
