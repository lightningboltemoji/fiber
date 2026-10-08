#include "fiber/browser/palette/tab_index_source.h"

#include <utility>

#import "FiberBridge/FiberRestorable.h"
#import "FiberBridge/FiberTabIndex.h"
#import "FiberBridge/FiberTabState.h"
#include "base/functional/bind.h"
#include "base/memory/ptr_util.h"
#include "base/no_destructor.h"
#include "base/strings/string_number_conversions.h"
#include "base/strings/string_util.h"
#include "base/strings/sys_string_conversions.h"
#include "base/task/sequenced_task_runner.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/sessions/tab_restore_service_factory.h"
#include "chrome/browser/ui/browser_live_tab_context.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#include "chrome/browser/ui/tabs/tab_strip_model.h"
#include "chrome/browser/ui/tabs/tab_strip_user_gesture_details.h"
#include "chrome/common/webui_url_constants.h"
#include "components/sessions/content/content_live_tab.h"
#include "components/sessions/core/tab_restore_types.h"
#include "components/tabs/public/tab_interface.h"
#include "content/public/common/url_constants.h"
#include "fiber/browser/palette/page_text.h"
#include "fiber/browser/window/fiber_browser_window.h"
#include "fiber/browser/window/tab_state.h"
#include "ui/base/window_open_disposition.h"

namespace fiber {

namespace {

// Restorable IDs: the kind, then which.
constexpr char kWindowIDPrefix[] = "window:";
constexpr char kSessionIDPrefix[] = "session:";

bool IsNewTabPage(const GURL& url) {
  return url.SchemeIs(content::kChromeUIScheme) &&
         url.host() == chrome::kChromeUINewTabHost;
}

FiberRestorablePage* PageFor(const std::u16string& title, const GURL& url) {
  NSString* display_url = base::SysUTF16ToNSString(DisplayURL(url));
  return [[FiberRestorablePage alloc]
      initWithTitle:title.empty() ? display_url
                                  : base::SysUTF16ToNSString(title)
                url:display_url];
}

// The indices of a closed window's tabs that the index lists: all but New Tab
// pages.
std::vector<size_t> ListedTabs(const sessions::tab_restore::Window& window) {
  std::vector<size_t> listed;
  for (size_t i = 0; i < window.tabs.size(); ++i) {
    const sessions::tab_restore::Tab& tab = *window.tabs[i];
    if (!tab.navigations.empty() &&
        !IsNewTabPage(
            tab.navigations[tab.normalized_navigation_index()].virtual_url())) {
      listed.push_back(i);
    }
  }
  return listed;
}

FiberRestorable* RestorableFor(const sessions::tab_restore::Window& window) {
  NSMutableArray<FiberRestorablePage*>* pages = [NSMutableArray array];
  for (size_t i : ListedTabs(window)) {
    const sessions::tab_restore::Tab& tab = *window.tabs[i];
    const sessions::SerializedNavigationEntry& entry =
        tab.navigations[tab.normalized_navigation_index()];
    [pages addObject:PageFor(entry.title(), entry.virtual_url())];
  }
  return [[FiberRestorable alloc]
       initWithID:base::SysUTF8ToNSString(kWindowIDPrefix +
                                          base::NumberToString(window.id.id()))
             kind:FiberRestorableKindWindow
             date:window.timestamp.ToNSDate()
      windowCount:1
            pages:pages];
}

FiberRestorable* RestorableFor(const PreviousSessions::Session& session) {
  NSMutableArray<FiberRestorablePage*>* pages = [NSMutableArray array];
  for (const std::vector<PreviousSessions::Tab>& tabs : session.windows) {
    for (const PreviousSessions::Tab& tab : tabs) {
      if (!IsNewTabPage(tab.url)) {
        [pages addObject:PageFor(tab.title, tab.url)];
      }
    }
  }
  return [[FiberRestorable alloc]
       initWithID:base::SysUTF8ToNSString(kSessionIDPrefix +
                                          session.path.value())
             kind:FiberRestorableKindSession
             date:session.ended.ToNSDate()
      windowCount:static_cast<NSInteger>(session.windows.size())
            pages:pages];
}

}  // namespace

// static
std::vector<std::unique_ptr<TabIndexSource>>& TabIndexSource::All() {
  static base::NoDestructor<std::vector<std::unique_ptr<TabIndexSource>>>
      sources;
  return *sources;
}

// static
TabIndexSource* TabIndexSource::AddWindow(FiberBrowserWindow* window) {
  Profile* profile = window->browser()->GetProfile();
  std::vector<std::unique_ptr<TabIndexSource>>& sources = All();
  auto it = std::ranges::find_if(sources, [profile](const auto& source) {
    return source->profile_ == profile;
  });
  TabIndexSource* source =
      it != sources.end()
          ? it->get()
          : sources.emplace_back(base::WrapUnique(new TabIndexSource(profile)))
                .get();
  source->windows_.push_back(window);
  return source;
}

// static
void TabIndexSource::RemoveWindow(FiberBrowserWindow* window) {
  std::vector<std::unique_ptr<TabIndexSource>>& sources = All();
  for (auto it = sources.begin(); it != sources.end(); ++it) {
    TabIndexSource* source = it->get();
    if (std::erase(source->windows_, window)) {
      if (source->windows_.empty()) {
        sources.erase(it);
      } else {
        source->TabsChanged();
      }
      return;
    }
  }
}

TabIndexSource::TabIndexSource(Profile* profile)
    : profile_(profile),
      index_([FiberTabIndexFactory tabIndex]),
      previous_sessions_(PreviousSessions::FromProfile(profile)) {
  if (sessions::TabRestoreService* service =
          TabRestoreServiceFactory::GetForProfile(profile)) {
    tab_restore_observation_.Observe(service);
    service->LoadTabsFromLastSession();
  }
  if (previous_sessions_) {
    previous_sessions_observation_.Observe(previous_sessions_.get());
  }
  RestorablesChanged();
}

TabIndexSource::~TabIndexSource() = default;

void TabIndexSource::TabsChanged() {
  if (is_send_pending_) {
    return;
  }
  is_send_pending_ = true;
  base::SequencedTaskRunner::GetCurrentDefault()->PostTask(
      FROM_HERE,
      base::BindOnce(&TabIndexSource::SendTabs, weak_factory_.GetWeakPtr()));
}

void TabIndexSource::ReadPageText(content::WebContents* web_contents) {
  if (PageText* page_text = PageTextFor(web_contents)) {
    page_text->Read();
  }
}

void TabIndexSource::RevealText(content::WebContents* web_contents,
                                const std::u16string& text) {
  if (PageText* page_text = PageTextFor(web_contents)) {
    page_text->Reveal(text);
  }
}

void TabIndexSource::UpdatePreviousSessions() {
  if (previous_sessions_) {
    previous_sessions_->Update();
  }
}

void TabIndexSource::Restore(BrowserWindowInterface* browser,
                             const std::string& restorable_id,
                             std::optional<size_t> page_index) {
  int id = 0;
  if (std::string_view rest = restorable_id;
      base::StartsWith(rest, kWindowIDPrefix) &&
      base::StringToInt(rest.substr(strlen(kWindowIDPrefix)), &id)) {
    RestoreClosedWindow(browser, SessionID::FromSerializedValue(id),
                        page_index);
  } else if (previous_sessions_ &&
             base::StartsWith(restorable_id, kSessionIDPrefix)) {
    previous_sessions_->Restore(
        base::FilePath(restorable_id.substr(strlen(kSessionIDPrefix))));
  }
}

void TabIndexSource::RestoreClosedWindow(BrowserWindowInterface* browser,
                                         SessionID id,
                                         std::optional<size_t> page_index) {
  sessions::TabRestoreService* service = tab_restore_observation_.GetSource();
  if (!service) {
    return;
  }
  std::optional<size_t> tab_index;
  size_t tab_count = 0;
  for (const auto& entry : service->entries()) {
    if (entry->id == id && entry->type == sessions::tab_restore::Type::WINDOW) {
      const auto& window =
          static_cast<const sessions::tab_restore::Window&>(*entry);
      std::vector<size_t> listed = ListedTabs(window);
      if (page_index && *page_index < listed.size()) {
        tab_index = listed[*page_index];
      }
      tab_count = window.tabs.size();
      break;
    }
  }
  std::vector<sessions::LiveTab*> restored = service->RestoreEntryById(
      BrowserLiveTabContext::From(browser), id, WindowOpenDisposition::UNKNOWN);
  // Unless one of its tabs didn't come back, they're in order.
  if (!tab_index || restored.size() != tab_count) {
    return;
  }
  tabs::TabInterface* tab = tabs::TabInterface::MaybeGetFromContents(
      &static_cast<sessions::ContentLiveTab*>(restored[*tab_index])
           ->GetWebContents());
  TabStripModel* model =
      tab ? tab->GetBrowserWindowInterface()->GetTabStripModel() : nullptr;
  if (model && model->GetIndexOfTab(tab) != TabStripModel::kNoTab) {
    model->ActivateTabAt(model->GetIndexOfTab(tab),
                         TabStripUserGestureDetails(
                             TabStripUserGestureDetails::GestureType::kOther));
  }
}

void TabIndexSource::TabRestoreServiceChanged(
    sessions::TabRestoreService* service) {
  RestorablesChanged();
}

void TabIndexSource::TabRestoreServiceDestroyed(
    sessions::TabRestoreService* service) {
  tab_restore_observation_.Reset();
}

void TabIndexSource::TabRestoreServiceLoaded(
    sessions::TabRestoreService* service) {
  RestorablesChanged();
}

void TabIndexSource::OnPreviousSessionsChanged() {
  RestorablesChanged();
}

void TabIndexSource::RestorablesChanged() {
  if (is_restorables_send_pending_) {
    return;
  }
  is_restorables_send_pending_ = true;
  base::SequencedTaskRunner::GetCurrentDefault()->PostTask(
      FROM_HERE, base::BindOnce(&TabIndexSource::SendRestorables,
                                weak_factory_.GetWeakPtr()));
}

void TabIndexSource::SendRestorables() {
  is_restorables_send_pending_ = false;
  NSMutableArray<FiberRestorable*>* restorables = [NSMutableArray array];
  if (sessions::TabRestoreService* service =
          tab_restore_observation_.GetSource()) {
    for (const auto& entry : service->entries()) {
      if (entry->type != sessions::tab_restore::Type::WINDOW) {
        continue;
      }
      const auto& window =
          static_cast<const sessions::tab_restore::Window&>(*entry);
      if (window.window_type == sessions::SessionWindow::TYPE_NORMAL &&
          !ListedTabs(window).empty()) {
        [restorables addObject:RestorableFor(window)];
      }
    }
  }
  if (previous_sessions_) {
    for (const PreviousSessions::Session* session :
         previous_sessions_->Offered()) {
      [restorables addObject:RestorableFor(*session)];
    }
  }
  [restorables sortUsingComparator:^NSComparisonResult(FiberRestorable* a,
                                                       FiberRestorable* b) {
    return [b.date compare:a.date];
  }];
  // What an ID names never changes.
  std::vector<std::string> ids;
  for (FiberRestorable* restorable in restorables) {
    ids.push_back(base::SysNSStringToUTF8(restorable.restorableID));
  }
  if (ids != sent_restorable_ids_) {
    sent_restorable_ids_ = std::move(ids);
    [index_ setRestorables:restorables];
  }
}

void TabIndexSource::SendTabs() {
  is_send_pending_ = false;
  // Which previous sessions are all open may have changed.
  RestorablesChanged();
  NSMutableArray<FiberTabState*>* tabs = [NSMutableArray array];
  std::map<int32_t, std::unique_ptr<PageText>> page_texts;
  for (FiberBrowserWindow* window : windows_) {
    TabStripModel* model = window->browser()->GetTabStripModel();
    for (int i = 0; i < model->count(); ++i) {
      tabs::TabInterface* tab = model->GetTabAtIndex(i);
      const int32_t tab_id = tab->GetHandle().raw_value();
      [tabs addObject:TabStateFor(tab)];
      auto it = page_texts_.find(tab_id);
      if (it != page_texts_.end() &&
          it->second->web_contents() == tab->GetContents()) {
        page_texts[tab_id] = std::move(it->second);
        continue;
      }
      page_texts[tab_id] = std::make_unique<PageText>(
          tab->GetContents(),
          base::BindRepeating(
              [](TabIndexSource* source, int32_t tab_id,
                 const std::string& text) {
                [source->index_ setPageText:base::SysUTF8ToNSString(text)
                               forTabWithID:tab_id];
              },
              base::Unretained(this), tab_id));
    }
  }
  page_texts_ = std::move(page_texts);
  [index_ setTabs:tabs];
}

PageText* TabIndexSource::PageTextFor(content::WebContents* web_contents) {
  tabs::TabInterface* tab =
      tabs::TabInterface::MaybeGetFromContents(web_contents);
  if (!tab) {
    return nullptr;
  }
  auto it = page_texts_.find(tab->GetHandle().raw_value());
  return it != page_texts_.end() ? it->second.get() : nullptr;
}

}  // namespace fiber
