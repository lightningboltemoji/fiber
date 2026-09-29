#include "fiber/browser/palette/tab_index_source.h"

#include <utility>

#import "FiberBridge/FiberTabIndex.h"
#import "FiberBridge/FiberTabState.h"
#include "base/functional/bind.h"
#include "base/memory/ptr_util.h"
#include "base/no_destructor.h"
#include "base/strings/sys_string_conversions.h"
#include "base/task/sequenced_task_runner.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#include "chrome/browser/ui/tabs/tab_strip_model.h"
#include "components/tabs/public/tab_interface.h"
#include "fiber/browser/palette/page_text.h"
#include "fiber/browser/window/fiber_browser_window.h"
#include "fiber/browser/window/tab_state.h"

namespace fiber {

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
    : profile_(profile), index_([FiberTabIndexFactory tabIndex]) {}

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

void TabIndexSource::SendTabs() {
  is_send_pending_ = false;
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
