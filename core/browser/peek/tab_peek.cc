#include "fiber/browser/peek/tab_peek.h"

#include <algorithm>
#include <optional>
#include <utility>

#include "base/containers/flat_map.h"
#include "base/containers/flat_set.h"
#include "base/uuid.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#include "chrome/browser/ui/tabs/tab_strip_model.h"
#include "components/tabs/public/tab_interface.h"
#include "content/public/browser/web_contents.h"
#include "content/public/browser/web_contents_user_data.h"
#include "fiber/browser/hooks/new_contents.h"
#include "fiber/browser/hooks/tab_strip_selection.h"
#include "fiber/browser/sessions/tab_extra_data.h"
#include "fiber/browser/split/tab_split.h"
#include "ui/gfx/range/range.h"

namespace fiber {

namespace {

// A peek's token, and on a tab a peek opened over, its latest peek's.
constexpr char kPeekKey[] = "fiber_peek";
constexpr char kLowerKey[] = "fiber_peek_lower";

class PeekData : public content::WebContentsUserData<PeekData> {
 public:
  ~PeekData() override = default;

  std::string peek_token;
  std::string lower_token;

 private:
  friend WebContentsUserData;

  explicit PeekData(content::WebContents* contents)
      : WebContentsUserData(*contents) {}

  WEB_CONTENTS_USER_DATA_KEY_DECL();
};

WEB_CONTENTS_USER_DATA_KEY_IMPL(PeekData);

const std::string& PeekToken(content::WebContents* contents) {
  static const std::string kNone;
  PeekData* data = PeekData::FromWebContents(contents);
  return data ? data->peek_token : kNone;
}

const std::string& LowerToken(content::WebContents* contents) {
  static const std::string kNone;
  PeekData* data = PeekData::FromWebContents(contents);
  return data ? data->lower_token : kNone;
}

PeekData& DataFor(content::WebContents* contents) {
  PeekData::CreateForWebContents(contents);
  return *PeekData::FromWebContents(contents);
}

void SetPeekToken(content::WebContents* contents, std::string token) {
  if (token == PeekToken(contents)) {
    return;
  }
  DataFor(contents).peek_token = token;
  SaveTabExtraData(contents, kPeekKey, token);
}

void SetLowerToken(content::WebContents* contents, std::string token) {
  if (token == LowerToken(contents)) {
    return;
  }
  DataFor(contents).lower_token = token;
  SaveTabExtraData(contents, kLowerKey, token);
}

bool Contains(const TabStripModel& model, tabs::TabInterface* tab) {
  return tab && model.GetIndexOfTab(tab) != TabStripModel::kNoTab;
}

}  // namespace

std::vector<PeekPair> Peeks(const TabStripModel& model) {
  // A split ends them all.
  if (ShownSplit(model)) {
    return {};
  }
  base::flat_map<std::string, tabs::TabInterface*> lowers;
  for (int i = 0; i < model.count(); ++i) {
    tabs::TabInterface* tab = model.GetTabAtIndex(i);
    const std::string& token = LowerToken(tab->GetContents());
    // Not over a peek: none opens from one.
    if (!token.empty() && PeekToken(tab->GetContents()).empty()) {
      lowers.emplace(token, tab);
    }
  }
  std::vector<PeekPair> pairs;
  base::flat_set<tabs::TabInterface*> paired;
  for (int i = 0; i < model.count(); ++i) {
    tabs::TabInterface* tab = model.GetTabAtIndex(i);
    const std::string& token = PeekToken(tab->GetContents());
    if (token.empty() || tab->IsPinned()) {
      continue;
    }
    auto lower = lowers.find(token);
    if (lower != lowers.end() && lower->second != tab &&
        paired.insert(lower->second).second) {
      pairs.push_back({lower->second, tab});
    }
  }
  return pairs;
}

tabs::TabInterface* PeekOf(const TabStripModel& model,
                           tabs::TabInterface* tab) {
  if (!tab || LowerToken(tab->GetContents()).empty()) {
    return nullptr;
  }
  for (const PeekPair& pair : Peeks(model)) {
    if (pair.lower == tab) {
      return pair.peek;
    }
  }
  return nullptr;
}

tabs::TabInterface* LowerTabOf(const TabStripModel& model,
                               tabs::TabInterface* tab) {
  if (!tab || PeekToken(tab->GetContents()).empty()) {
    return nullptr;
  }
  for (const PeekPair& pair : Peeks(model)) {
    if (pair.peek == tab) {
      return pair.lower;
    }
  }
  return nullptr;
}

bool ArePaired(const TabStripModel& model,
               tabs::TabInterface* a,
               tabs::TabInterface* b) {
  return a && b &&
         std::ranges::any_of(Peeks(model), [&](const PeekPair& pair) {
           return (pair.lower == a && pair.peek == b) ||
                  (pair.lower == b && pair.peek == a);
         });
}

tabs::TabInterface* UserTab(const TabStripModel& model,
                            tabs::TabInterface* tab) {
  tabs::TabInterface* lower = LowerTabOf(model, tab);
  return lower ? lower : tab;
}

tabs::TabInterface* ShownTab(const TabStripModel& model,
                             tabs::TabInterface* tab) {
  tabs::TabInterface* peek = PeekOf(model, tab);
  return peek ? peek : tab;
}

bool WasPeek(content::WebContents* contents) {
  return !PeekToken(contents).empty();
}

bool NeedsSettling(const TabStripModel& model) {
  const std::vector<PeekPair> pairs = Peeks(model);
  for (int i = 0; i < model.count(); ++i) {
    tabs::TabInterface* tab = model.GetTabAtIndex(i);
    if (!PeekToken(tab->GetContents()).empty() &&
        std::ranges::none_of(pairs, [tab](const PeekPair& pair) {
          return pair.peek == tab;
        })) {
      return true;
    }
  }
  tabs::TabInterface* active = model.GetActiveTab();
  return std::ranges::any_of(pairs, [active](const PeekPair& pair) {
    return pair.lower == active;
  });
}

void SettlePeeks(TabStripModel* model) {
  const std::vector<PeekPair> pairs = Peeks(*model);
  for (int i = 0; i < model->count(); ++i) {
    tabs::TabInterface* tab = model->GetTabAtIndex(i);
    if (!PeekToken(tab->GetContents()).empty() &&
        std::ranges::none_of(pairs, [tab](const PeekPair& pair) {
          return pair.peek == tab;
        })) {
      SetPeekToken(tab->GetContents(), std::string());
    }
  }
  tabs::TabInterface* active = model->GetActiveTab();
  for (const PeekPair& pair : pairs) {
    if (pair.lower == active) {
      model->ActivateTabAt(model->GetIndexOfTab(pair.peek));
      break;
    }
  }
}

void ExpandPeek(TabStripModel* model, tabs::TabInterface* peek) {
  tabs::TabInterface* lower = LowerTabOf(*model, peek);
  if (!lower) {
    return;
  }
  SetPeekToken(peek->GetContents(), std::string());
  const int from = model->GetIndexOfTab(peek);
  const int after = model->GetIndexOfTab(lower) + 1;
  // Chrome keeps it after the pinned tabs, beside a pin's.
  const int to = from < after ? after - 1 : after;
  if (to != from) {
    model->MoveWebContentsAt(from, to, /*select_after_move=*/false);
  }
}

void ExpandPeeks(TabStripModel* model) {
  for (const PeekPair& pair : Peeks(*model)) {
    ExpandPeek(model, pair.peek);
  }
}

void SavePeekData(content::WebContents* contents) {
  if (const std::string& token = PeekToken(contents); !token.empty()) {
    SaveTabExtraData(contents, kPeekKey, token);
  }
  if (const std::string& token = LowerToken(contents); !token.empty()) {
    SaveTabExtraData(contents, kLowerKey, token);
  }
}

void AddPeekExtraData(content::WebContents* contents,
                      std::map<std::string, std::string>& extra_data) {
  if (const std::string& token = PeekToken(contents); !token.empty()) {
    extra_data[kPeekKey] = token;
  }
  if (const std::string& token = LowerToken(contents); !token.empty()) {
    extra_data[kLowerKey] = token;
  }
}

void RestorePeekExtraData(
    content::WebContents* contents,
    const std::map<std::string, std::string>& extra_data) {
  auto peek = extra_data.find(kPeekKey);
  auto lower = extra_data.find(kLowerKey);
  if (peek == extra_data.end() && lower == extra_data.end()) {
    return;
  }
  PeekData& data = DataFor(contents);
  data.peek_token = peek != extra_data.end() ? peek->second : std::string();
  data.lower_token = lower != extra_data.end() ? lower->second : std::string();
}

namespace {

bool CanPeekOver(BrowserWindowInterface* browser,
                 content::WebContents* source) {
  if (!browser || !source ||
      browser->GetType() != BrowserWindowInterface::Type::TYPE_NORMAL) {
    return false;
  }
  TabStripModel* model = browser->GetTabStripModel();
  tabs::TabInterface* tab = model->GetActiveTab();
  return tab && tab->GetContents() == source && !ShownSplit(*model) &&
         !LowerTabOf(*model, tab) && !PeekOf(*model, tab);
}

void MarkPeek(content::WebContents* source,
              content::WebContents* new_contents) {
  std::string token = base::Uuid::GenerateRandomV4().AsLowercaseString();
  SetLowerToken(source, token);
  // Saved once it's in the window (see SavePeekData()).
  DataFor(new_contents).peek_token = std::move(token);
}

}  // namespace

void WillAddNewContents(BrowserWindowInterface* browser,
                        content::WebContents* source,
                        content::WebContents* new_contents,
                        WindowOpenDisposition disposition,
                        bool user_gesture) {
  if (new_contents && user_gesture &&
      disposition == WindowOpenDisposition::kNewForegroundTab &&
      CanPeekOver(browser, source)) {
    MarkPeek(source, new_contents);
  }
}

bool TakePeekDisposition(WindowOpenDisposition& disposition) {
  if (disposition != WindowOpenDisposition::kNewPeek) {
    return false;
  }
  disposition = WindowOpenDisposition::kNewForegroundTab;
  return true;
}

void WillAddPeekContents(BrowserWindowInterface* browser,
                         content::WebContents* source,
                         content::WebContents* new_contents) {
  if (new_contents && CanPeekOver(browser, source)) {
    MarkPeek(source, new_contents);
  }
}

std::optional<int> TabToReturnToAfterClosing(const TabStripModel& model,
                                             const gfx::Range& closing) {
  for (size_t i = closing.start(); i < closing.end(); ++i) {
    tabs::TabInterface* lower =
        LowerTabOf(model, model.GetTabAtIndex(static_cast<int>(i)));
    if (!Contains(model, lower)) {
      continue;
    }
    const int index = model.GetIndexOfTab(lower);
    if (!closing.Contains(gfx::Range(index))) {
      return index;
    }
  }
  return std::nullopt;
}

}  // namespace fiber
