#ifndef FIBER_BROWSER_PEEK_TAB_PEEK_H_
#define FIBER_BROWSER_PEEK_TAB_PEEK_H_

#include <map>
#include <string>
#include <vector>

#include "base/memory/raw_ptr.h"

class TabStripModel;

namespace content {
class WebContents;
}

namespace tabs {
class TabInterface;
}

namespace fiber {

// A link a page opens in a new tab opens over it instead, as a peek: an
// ordinary tab, active while it shows, that the window shows as a card over
// the tab it came from, its lower tab (see FiberPeek). To the user the two
// are one tab, the lower one. They share a token, kept in their sessions, so
// what pairs them is the token and not their places.
//
// No peek opens from a peek, or while the window has a split. Whatever
// separates a pair (the lower tab closing or leaving the window, the peek
// leaving it or being pinned, a split) makes the peek an ordinary tab where
// it is. Its lower tab keeps the token, for ⇧⌘T to bring the peek back over it.

struct PeekPair {
  raw_ptr<tabs::TabInterface> lower;
  raw_ptr<tabs::TabInterface> peek;
};

// The window's pairs, as they are once settled (see SettlePeeks()).
std::vector<PeekPair> Peeks(const TabStripModel& model);
tabs::TabInterface* PeekOf(const TabStripModel& model, tabs::TabInterface* tab);
tabs::TabInterface* LowerTabOf(const TabStripModel& model,
                               tabs::TabInterface* tab);
bool ArePaired(const TabStripModel& model,
               tabs::TabInterface* a,
               tabs::TabInterface* b);

// What the user means by `tab`: the tab it's over for a peek, else `tab`.
tabs::TabInterface* UserTab(const TabStripModel& model,
                            tabs::TabInterface* tab);
// What activating `tab` shows: its peek if it has one, else `tab`.
tabs::TabInterface* ShownTab(const TabStripModel& model,
                             tabs::TabInterface* tab);

// Whether the tab was marked a peek, paired or not, for a tab that has left
// its window.
bool WasPeek(content::WebContents* contents);

// Whether SettlePeeks() has anything to do.
bool NeedsSettling(const TabStripModel& model);
// Makes a tab whose token pairs it with none (one restored without its lower
// tab, or separated from it) an ordinary tab, and a lower tab that's active
// give way to its peek.
void SettlePeeks(TabStripModel* model);

// Makes the peek an ordinary tab, just after its lower tab, as a link opened
// in front would be.
void ExpandPeek(TabStripModel* model, tabs::TabInterface* peek);
void ExpandPeeks(TabStripModel* model);

// Keeps the tab's token in its session, once it's in a window. Until then
// Chrome's session doesn't know the tab.
void SavePeekData(content::WebContents* contents);

// The token, for the tab's session and closed-tab history (see
// hooks/tab_extra_data.h).
void AddPeekExtraData(content::WebContents* contents,
                      std::map<std::string, std::string>& extra_data);
void RestorePeekExtraData(
    content::WebContents* contents,
    const std::map<std::string, std::string>& extra_data);

}  // namespace fiber

#endif  // FIBER_BROWSER_PEEK_TAB_PEEK_H_
