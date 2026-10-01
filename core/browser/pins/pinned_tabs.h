#ifndef FIBER_BROWSER_PINS_PINNED_TABS_H_
#define FIBER_BROWSER_PINS_PINNED_TABS_H_

#import <Foundation/Foundation.h>

#include <string>
#include <string_view>
#include <vector>

#include "base/functional/callback.h"
#include "base/memory/raw_ptr.h"
#include "base/memory/weak_ptr.h"
#include "base/scoped_observation.h"
#include "chrome/browser/ui/tabs/tab_strip_model_observer.h"
#include "components/tabs/public/tab_interface.h"
#include "fiber/browser/pins/pin_store.h"

@class FiberPinState;

class BrowserWindowInterface;

namespace fiber {

// Keeps a window's pinned tabs in step with its profile's pins: one tab per
// pin, in the pins' order. A tab Chrome pins (the Tab menu, an extension)
// becomes a new pin's; unpinning a pin's tab unpins its page everywhere.
class PinnedTabs : public PinStore::Observer, public TabStripModelObserver {
 public:
  // `on_changed` is called when the pins change; the window observes its tab
  // strip after this does, so it sees which tab is whose.
  PinnedTabs(BrowserWindowInterface* browser,
             PinStore* store,
             base::RepeatingClosure on_changed);
  PinnedTabs(const PinnedTabs&) = delete;
  PinnedTabs& operator=(const PinnedTabs&) = delete;
  ~PinnedTabs() override;

  // What the window shows of the pins, in order.
  NSArray<FiberPinState*>* GetPinStates() const;

  // What the user does with the window's pins (see FiberWindowActions).
  void PinTab(int32_t tab_id);
  void Open(std::string_view pin_id);
  void Reset(std::string_view pin_id);
  void UpdateURL(std::string_view pin_id);
  void Unpin(std::string_view pin_id);
  void Move(std::string_view pin_id, size_t index);

  // PinStore::Observer:
  void OnPinsChanged() override;

  // TabStripModelObserver:
  void OnTabStripModelChanged(
      TabStripModel* tab_strip_model,
      const TabStripModelChange& change,
      const TabStripSelectionChange& selection) override;
  void OnTabChangedAt(tabs::TabInterface* tab,
                      TabChangeType change_type) override;
  void OnTabPinnedStateChanged(tabs::TabInterface* tab, int index) override;

 private:
  TabStripModel* model() const;
  // The pin's tab here, if it's open.
  tabs::TabInterface* TabForPin(std::string_view pin_id) const;
  // The pin whose page the tab is, if it's still pinned.
  const Pin* PinForTab(tabs::TabInterface* tab) const;
  // Makes the pinned tab a new pin's page.
  void Adopt(tabs::TabInterface* tab);
  void TabInserted(tabs::TabInterface* tab);
  // Makes the tab no pin's, and unpins it once the tab strip can change.
  void Release(tabs::TabInterface* tab);
  // Keeps the pin's title and icon those of its page while the tab is on it.
  void UpdatePinFromTab(tabs::TabInterface* tab);
  // A pin's tab moved: the pin goes before the next pin open here, or after
  // the one before it.
  void TabMoved(tabs::TabInterface* tab);

  // The tab strip can't change while it tells its observers of a change, so
  // unpinning and reordering wait for Arrange().
  void ScheduleArrange();
  // Unpins the released tabs and puts the pins' tabs in the pins' order.
  void Arrange();

  const raw_ptr<BrowserWindowInterface> browser_;
  const raw_ptr<PinStore> store_;
  const base::RepeatingClosure on_changed_;
  // The pin whose tab Open() is adding.
  std::string opening_pin_id_;
  std::vector<tabs::TabHandle> tabs_to_unpin_;
  bool is_arranging_ = false;
  bool is_arrange_pending_ = false;
  base::ScopedObservation<PinStore, PinStore::Observer> store_observation_{
      this};
  base::WeakPtrFactory<PinnedTabs> weak_factory_{this};
};

}  // namespace fiber

#endif  // FIBER_BROWSER_PINS_PINNED_TABS_H_
