#include "fiber/browser/pins/pinned_tabs.h"

#include <utility>

#import "FiberBridge/FiberPinState.h"
#include "base/auto_reset.h"
#include "base/functional/bind.h"
#include "base/strings/escape.h"
#include "base/strings/sys_string_conversions.h"
#include "base/task/sequenced_task_runner.h"
#include "base/uuid.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#include "chrome/browser/ui/navigator/browser_navigator.h"
#include "chrome/browser/ui/navigator/browser_navigator_params.h"
#include "chrome/browser/ui/tabs/tab_enums.h"
#include "chrome/browser/ui/tabs/tab_strip_model.h"
#include "chrome/browser/ui/tabs/tab_strip_user_gesture_details.h"
#include "components/favicon/content/content_favicon_driver.h"
#include "components/url_formatter/url_formatter.h"
#include "content/public/browser/navigation_controller.h"
#include "content/public/browser/navigation_entry.h"
#include "content/public/browser/web_contents.h"
#include "fiber/browser/favicons/favicon_image.h"
#include "fiber/browser/pins/pinned_tab_data.h"
#include "ui/base/page_transition_types.h"
#include "ui/base/window_open_disposition.h"

namespace fiber {

namespace {

gfx::Image TabFavicon(content::WebContents* contents) {
  favicon::ContentFaviconDriver* driver =
      favicon::ContentFaviconDriver::FromWebContents(contents);
  return driver && driver->FaviconIsValid() ? driver->GetFavicon()
                                            : gfx::Image();
}

// Whether the tab is on the page at `url`, or one `url` redirected to,
// fragments aside.
bool IsOnPage(content::WebContents* contents, const GURL& url) {
  content::NavigationEntry* entry =
      contents->GetController().GetLastCommittedEntry();
  if (!entry || entry->IsInitialEntry()) {
    return false;
  }
  const GURL page = url.GetWithoutRef();
  return entry->GetURL().GetWithoutRef() == page ||
         entry->GetOriginalRequestURL().GetWithoutRef() == page;
}

NSString* DisplayURL(const GURL& url) {
  return base::SysUTF16ToNSString(url_formatter::FormatUrl(
      url,
      url_formatter::kFormatUrlOmitDefaults |
          url_formatter::kFormatUrlOmitHTTPS |
          url_formatter::kFormatUrlOmitTrivialSubdomains,
      base::UnescapeRule::SPACES, nullptr, nullptr, nullptr));
}

}  // namespace

PinnedTabs::PinnedTabs(BrowserWindowInterface* browser,
                       PinStore* store,
                       base::RepeatingClosure on_changed)
    : browser_(browser), store_(store), on_changed_(std::move(on_changed)) {
  store_observation_.Observe(store_);
  model()->AddObserver(this);
}

PinnedTabs::~PinnedTabs() = default;

NSArray<FiberPinState*>* PinnedTabs::GetPinStates() const {
  NSMutableArray<FiberPinState*>* states = [NSMutableArray array];
  for (const Pin& pin : store_->pins()) {
    tabs::TabInterface* tab = TabForPin(pin.id);
    content::WebContents* contents = tab ? tab->GetContents() : nullptr;
    gfx::Image favicon = contents ? TabFavicon(contents) : gfx::Image();
    const GURL& favicon_page =
        favicon.IsEmpty() ? pin.url : contents->GetLastCommittedURL();
    if (favicon.IsEmpty()) {
      favicon = pin.icon;
    }
    [states
        addObject:[[FiberPinState alloc]
                       initWithID:base::SysUTF8ToNSString(pin.id)
                            title:base::SysUTF16ToNSString(pin.title)
                              url:DisplayURL(pin.url)
                          favicon:favicon.IsEmpty()
                                      ? nil
                                      : FaviconImage(favicon, favicon_page)
                            tabID:tab ? tab->GetHandle().raw_value()
                                      : tabs::TabHandle::NullValue
                          loading:contents && contents->ShouldShowLoadingUI()
                      atPinnedURL:contents && IsOnPage(contents, pin.url)]];
  }
  return states;
}

void PinnedTabs::PinTab(int32_t tab_id) {
  const int index = model()->GetIndexOfTab(tabs::TabHandle(tab_id).Get());
  if (index != TabStripModel::kNoTab) {
    // OnTabPinnedStateChanged() makes it a new pin's.
    model()->SetTabPinned(index, true);
  }
}

void PinnedTabs::Open(std::string_view pin_id) {
  TabStripModel* model = this->model();
  if (tabs::TabInterface* tab = TabForPin(pin_id)) {
    model->ActivateTabAt(model->GetIndexOfTab(tab),
                         TabStripUserGestureDetails(
                             TabStripUserGestureDetails::GestureType::kMouse));
    return;
  }
  const std::optional<size_t> pin_index = store_->IndexOf(pin_id);
  if (!pin_index) {
    return;
  }
  // After the tabs of the pins before it.
  int index = 0;
  for (int i = 0; i < model->IndexOfFirstNonPinnedTab(); ++i) {
    const Pin* pin = PinForTab(model->GetTabAtIndex(i));
    if (pin && store_->IndexOf(pin->id) < pin_index) {
      index = i + 1;
    }
  }
  NavigateParams params(browser_, store_->pins()[*pin_index].url,
                        ui::PAGE_TRANSITION_AUTO_BOOKMARK);
  params.disposition = WindowOpenDisposition::NEW_FOREGROUND_TAB;
  params.tabstrip_index = index;
  params.tabstrip_add_types = AddTabTypes::ADD_ACTIVE |
                              AddTabTypes::ADD_PINNED |
                              AddTabTypes::ADD_FORCE_INDEX;
  base::AutoReset<std::string> opening(&opening_pin_id_, std::string(pin_id));
  Navigate(&params);
}

void PinnedTabs::Reset(std::string_view pin_id) {
  tabs::TabInterface* tab = TabForPin(pin_id);
  const Pin* pin = store_->Find(pin_id);
  if (!pin) {
    return;
  }
  const GURL url = pin->url;
  Open(pin_id);
  if (tab) {
    tab->GetContents()->GetController().LoadURL(
        url, content::Referrer(), ui::PAGE_TRANSITION_AUTO_BOOKMARK,
        std::string());
  }
}

void PinnedTabs::UpdateURL(std::string_view pin_id) {
  tabs::TabInterface* tab = TabForPin(pin_id);
  if (!tab) {
    return;
  }
  content::WebContents* contents = tab->GetContents();
  store_->Update(pin_id, contents->GetLastCommittedURL(), contents->GetTitle(),
                 TabFavicon(contents));
}

void PinnedTabs::Unpin(std::string_view pin_id) {
  // Each window lets go of its tab in OnPinsChanged().
  store_->Remove(pin_id);
}

void PinnedTabs::Move(std::string_view pin_id, size_t index) {
  store_->Move(pin_id, index);
}

void PinnedTabs::OnPinsChanged() {
  TabStripModel* model = this->model();
  for (int i = 0; i < model->IndexOfFirstNonPinnedTab(); ++i) {
    tabs::TabInterface* tab = model->GetTabAtIndex(i);
    std::string pin_id = PinIDForTab(tab->GetContents());
    if (!pin_id.empty() && !store_->Find(pin_id)) {
      Release(tab);
    }
  }
  ScheduleArrange();
  on_changed_.Run();
}

void PinnedTabs::OnTabStripModelChanged(
    TabStripModel* tab_strip_model,
    const TabStripModelChange& change,
    const TabStripSelectionChange& selection) {
  switch (change.type()) {
    case TabStripModelChange::kInserted:
      for (const TabStripModelChange::ContentsWithIndex& inserted :
           change.GetInsert()->contents) {
        TabInserted(inserted.tab);
      }
      break;
    case TabStripModelChange::kReplaced: {
      // Discarding a tab can replace its contents.
      const TabStripModelChange::Replace* replace = change.GetReplace();
      std::string pin_id = PinIDForTab(replace->old_contents);
      if (!pin_id.empty()) {
        SetPinIDForTab(replace->new_contents, pin_id);
      }
      break;
    }
    case TabStripModelChange::kMoved:
      if (!is_arranging_) {
        TabMoved(change.GetMove()->tab);
      }
      break;
    default:
      break;
  }
}

void PinnedTabs::OnTabChangedAt(tabs::TabInterface* tab,
                                TabChangeType change_type) {
  if (change_type == TabChangeType::kAll) {
    UpdatePinFromTab(tab);
  }
}

void PinnedTabs::OnTabPinnedStateChanged(tabs::TabInterface* tab, int index) {
  content::WebContents* contents = tab->GetContents();
  const std::string pin_id = PinIDForTab(contents);
  if (tab->IsPinned()) {
    if (pin_id.empty()) {
      Adopt(tab);
    }
  } else if (!pin_id.empty()) {
    SetPinIDForTab(contents, std::string());
    store_->Remove(pin_id);
  }
}

TabStripModel* PinnedTabs::model() const {
  return browser_->GetTabStripModel();
}

tabs::TabInterface* PinnedTabs::TabForPin(std::string_view pin_id) const {
  TabStripModel* model = this->model();
  for (int i = 0; i < model->IndexOfFirstNonPinnedTab(); ++i) {
    tabs::TabInterface* tab = model->GetTabAtIndex(i);
    if (PinIDForTab(tab->GetContents()) == pin_id) {
      return tab;
    }
  }
  return nullptr;
}

const Pin* PinnedTabs::PinForTab(tabs::TabInterface* tab) const {
  return tab->IsPinned() ? store_->Find(PinIDForTab(tab->GetContents()))
                         : nullptr;
}

void PinnedTabs::Adopt(tabs::TabInterface* tab) {
  content::WebContents* contents = tab->GetContents();
  Pin pin;
  pin.id = base::Uuid::GenerateRandomV4().AsLowercaseString();
  pin.url = contents->GetVisibleURL();
  pin.title = contents->GetTitle();
  pin.icon = TabFavicon(contents);
  // Before the next pin open here, or last: Chrome pins a tab at the end.
  size_t index = store_->pins().size();
  TabStripModel* model = this->model();
  for (int i = model->GetIndexOfTab(tab) + 1;
       i < model->IndexOfFirstNonPinnedTab(); ++i) {
    if (const Pin* next = PinForTab(model->GetTabAtIndex(i))) {
      index = *store_->IndexOf(next->id);
      break;
    }
  }
  SetPinIDForTab(contents, pin.id);
  store_->Add(std::move(pin), index);
}

void PinnedTabs::TabInserted(tabs::TabInterface* tab) {
  content::WebContents* contents = tab->GetContents();
  std::string pin_id = PinIDForTab(contents);
  if (!tab->IsPinned()) {
    if (!pin_id.empty()) {
      SetPinIDForTab(contents, std::string());
    }
    return;
  }
  if (pin_id.empty()) {
    pin_id = opening_pin_id_;
  }
  if (pin_id.empty()) {
    Adopt(tab);
    return;
  }
  // A restored tab whose pin is gone, or whose pin is open here already.
  tabs::TabInterface* open = nullptr;
  TabStripModel* model = this->model();
  for (int i = 0; i < model->IndexOfFirstNonPinnedTab() && !open; ++i) {
    tabs::TabInterface* other = model->GetTabAtIndex(i);
    if (other != tab && PinIDForTab(other->GetContents()) == pin_id) {
      open = other;
    }
  }
  if (open || !store_->Find(pin_id)) {
    Release(tab);
    return;
  }
  // Also tells its session which window it's in now.
  SetPinIDForTab(contents, pin_id);
  ScheduleArrange();
}

void PinnedTabs::Release(tabs::TabInterface* tab) {
  SetPinIDForTab(tab->GetContents(), std::string());
  tabs_to_unpin_.push_back(tab->GetHandle());
  ScheduleArrange();
}

void PinnedTabs::UpdatePinFromTab(tabs::TabInterface* tab) {
  const Pin* pin = PinForTab(tab);
  content::WebContents* contents = tab->GetContents();
  if (!pin || !IsOnPage(contents, pin->url)) {
    return;
  }
  const std::string pin_id = pin->id;
  const GURL url = pin->url;
  store_->Update(pin_id, url, contents->GetTitle(), TabFavicon(contents));
}

void PinnedTabs::TabMoved(tabs::TabInterface* tab) {
  const Pin* pin = PinForTab(tab);
  if (!pin) {
    return;
  }
  const std::string pin_id = pin->id;
  const size_t from = *store_->IndexOf(pin_id);
  TabStripModel* model = this->model();
  const int index = model->GetIndexOfTab(tab);
  for (int i = index + 1; i < model->IndexOfFirstNonPinnedTab(); ++i) {
    if (const Pin* next = PinForTab(model->GetTabAtIndex(i))) {
      const size_t to = *store_->IndexOf(next->id);
      store_->Move(pin_id, to > from ? to - 1 : to);
      return;
    }
  }
  for (int i = index - 1; i >= 0; --i) {
    if (const Pin* previous = PinForTab(model->GetTabAtIndex(i))) {
      const size_t to = *store_->IndexOf(previous->id);
      store_->Move(pin_id, to < from ? to + 1 : to);
      return;
    }
  }
}

void PinnedTabs::ScheduleArrange() {
  if (is_arrange_pending_) {
    return;
  }
  is_arrange_pending_ = true;
  base::SequencedTaskRunner::GetCurrentDefault()->PostTask(
      FROM_HERE,
      base::BindOnce(&PinnedTabs::Arrange, weak_factory_.GetWeakPtr()));
}

void PinnedTabs::Arrange() {
  is_arrange_pending_ = false;
  base::AutoReset<bool> arranging(&is_arranging_, true);
  TabStripModel* model = this->model();
  for (tabs::TabHandle handle : std::exchange(tabs_to_unpin_, {})) {
    tabs::TabInterface* tab = handle.Get();
    const int index =
        tab ? model->GetIndexOfTab(tab) : TabStripModel::kNoTab;
    if (index != TabStripModel::kNoTab && tab->IsPinned() &&
        PinIDForTab(tab->GetContents()).empty()) {
      model->SetTabPinned(index, false);
    }
  }
  std::vector<tabs::TabInterface*> ordered;
  for (const Pin& pin : store_->pins()) {
    if (tabs::TabInterface* tab = TabForPin(pin.id)) {
      ordered.push_back(tab);
    }
  }
  for (size_t i = 0; i < ordered.size(); ++i) {
    const int index = model->GetIndexOfTab(ordered[i]);
    if (index != static_cast<int>(i)) {
      model->MoveWebContentsAt(index, i, /*select_after_move=*/false);
    }
  }
}

}  // namespace fiber
