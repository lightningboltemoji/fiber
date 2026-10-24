#include "fiber/browser/split/tab_split.h"

#include <algorithm>
#include <vector>

#include "chrome/browser/ui/tabs/tab_strip_model.h"
#include "chrome/browser/ui/tabs/tab_strip_user_gesture_details.h"
#include "components/split_tabs/split_tab_visual_data.h"
#include "components/tabs/public/split_tab_data.h"
#include "components/tabs/public/tab_interface.h"
#include "content/public/browser/web_contents.h"
#include "fiber/browser/pins/pinned_tab_data.h"

namespace fiber {

namespace {

std::vector<tabs::TabInterface*> SplitTabs(const TabStripModel& model,
                                           split_tabs::SplitTabId split) {
  return model.GetSplitData(split)->ListTabs();
}

double ShownRatio(const TabStripModel& model) {
  std::optional<split_tabs::SplitTabId> shown = ShownSplit(model);
  return shown ? model.GetSplitData(*shown)->visual_data()->split_ratio() : 0.5;
}

bool Contains(const TabStripModel& model, tabs::TabInterface* tab) {
  return tab && model.GetIndexOfTab(tab) != TabStripModel::kNoTab;
}

bool IsKeptBesidePin(tabs::TabInterface* tab) {
  return IsBesidePin(tab->GetContents());
}

// Any tab in no split can be a split's left, a pin's or a shelf page's too,
// but for one kept beside a pin.
bool CanBeLeft(tabs::TabInterface* tab) {
  return !tab->IsSplit() && !IsKeptBesidePin(tab);
}

// An ordinary tab in no split can be its right, or one kept beside a pin.
bool CanBeRight(tabs::TabInterface* tab) {
  return !tab->IsSplit() && (!tab->IsPinned() || IsKeptBesidePin(tab));
}

bool IsPaired(const TabStripModel& model,
              tabs::TabInterface* left,
              tabs::TabInterface* right) {
  std::optional<split_tabs::SplitTabId> split = left->GetSplit();
  return split && split == right->GetSplit() &&
         model.GetIndexOfTab(left) < model.GetIndexOfTab(right);
}

// For `right`, whose split's left has gone, the ordinary tab closing a tab
// goes to: the one after it or before it, or after a pin's, the one used
// last.
tabs::TabInterface* LeftInPlaceOf(const TabStripModel& model,
                                  tabs::TabInterface* right) {
  auto ordinary_at = [&](int index) -> tabs::TabInterface* {
    if (!model.ContainsIndex(index)) {
      return nullptr;
    }
    tabs::TabInterface* tab = model.GetTabAtIndex(index);
    return tab != right && !tab->IsPinned() && !tab->IsSplit() ? tab : nullptr;
  };
  if (!right->IsPinned()) {
    const int index = model.GetIndexOfTab(right);
    if (tabs::TabInterface* tab = ordinary_at(index + 1)) {
      return tab;
    }
    if (tabs::TabInterface* tab = ordinary_at(index - 1)) {
      return tab;
    }
  }
  tabs::TabInterface* last_used = nullptr;
  for (int i = model.IndexOfFirstNonPinnedTab(); i < model.count(); ++i) {
    tabs::TabInterface* tab = ordinary_at(i);
    if (tab &&
        (!last_used || tab->GetContents()->GetLastActiveTime() >
                           last_used->GetContents()->GetLastActiveTime())) {
      last_used = tab;
    }
  }
  return last_used;
}

// Splits `left` and `right`, in place of the shown split, leaving `left`
// where it is.
void Pair(TabStripModel* model,
          tabs::TabInterface* left,
          tabs::TabInterface* right,
          double ratio) {
  split_tabs::SplitTabId id = split_tabs::SplitTabId::GenerateNew();
  if (std::optional<split_tabs::SplitTabId> shown = ShownSplit(*model)) {
    id = *shown;
    model->RemoveSplit(*shown);
  }
  for (tabs::TabInterface* tab : {left, right}) {
    if (std::optional<split_tabs::SplitTabId> split = tab->GetSplit()) {
      model->RemoveSplit(*split);
    }
  }
  // A split takes its first tab's pinning, so beside a pin's tab the right is
  // pinned too, though it's no pin.
  const bool is_beside_pin = left->IsPinned();
  SetBesidePin(right->GetContents(), is_beside_pin);
  if (right->IsPinned() && !is_beside_pin) {
    model->SetTabPinned(model->GetIndexOfTab(right), false);
  }
  // Pinned or not as the left is, it moves beside it; otherwise the split
  // moves it there.
  if (right->IsPinned() == left->IsPinned()) {
    const int left_index = model->GetIndexOfTab(left);
    const int right_index = model->GetIndexOfTab(right);
    const int beside = right_index < left_index ? left_index : left_index + 1;
    if (right_index != beside) {
      model->MoveWebContentsAt(right_index, beside,
                               /*select_after_move=*/false);
    }
  }
  // Restoring rather than adding keeps the split's ID, and skips Chrome's
  // views-only promo.
  model->RestoreSplit(id,
                      {model->GetIndexOfTab(left), model->GetIndexOfTab(right)},
                      split_tabs::SplitTabVisualData(
                          split_tabs::SplitTabLayout::kSideBySide, ratio));
}

}  // namespace

std::optional<split_tabs::SplitTabId> ShownSplit(const TabStripModel& model) {
  if (const tabs::TabInterface* active = model.GetActiveTab();
      active && active->IsSplit()) {
    return active->GetSplit();
  }
  for (int i = 0; i < model.count(); ++i) {
    if (std::optional<split_tabs::SplitTabId> split = model.GetSplitForTab(i)) {
      return split;
    }
  }
  return std::nullopt;
}

tabs::TabInterface* KeptTab(const TabStripModel& model) {
  std::optional<split_tabs::SplitTabId> split = ShownSplit(model);
  return split ? SplitTabs(model, *split).back() : nullptr;
}

std::optional<SplitPlan> PlanSplit(const TabStripModel& model,
                                   const std::optional<EndedSplit>& ended) {
  tabs::TabInterface* active = model.GetActiveTab();
  if (tabs::TabInterface* right = ended ? ended->right.Get() : nullptr;
      Contains(model, right) && CanBeRight(right)) {
    tabs::TabInterface* left = ended->left.Get();
    const bool is_left_gone = !Contains(model, left);
    if (active && active != right && CanBeLeft(active)) {
      left = active;
    } else if (is_left_gone || !CanBeLeft(left)) {
      left = LeftInPlaceOf(model, right);
    }
    if (!left) {
      return std::nullopt;
    }
    return SplitPlan{left, right, ended->ratio,
                     ended->was_left_active && is_left_gone && left != active};
  }
  std::optional<split_tabs::SplitTabId> split = ShownSplit(model);
  if (!split) {
    return std::nullopt;
  }
  const std::vector<tabs::TabInterface*> tabs = SplitTabs(model, *split);
  const double ratio = model.GetSplitData(*split)->visual_data()->split_ratio();
  if (active && CanBeLeft(active)) {
    return SplitPlan{active, tabs.back(), ratio, false};
  }
  return SplitPlan{tabs.front(), tabs.back(), ratio, false};
}

bool HasStrandedTab(const TabStripModel& model) {
  for (int i = 0; i < model.IndexOfFirstNonPinnedTab(); ++i) {
    tabs::TabInterface* tab = model.GetTabAtIndex(i);
    if (IsKeptBesidePin(tab) && !tab->IsSplit()) {
      return true;
    }
  }
  return false;
}

void ReleaseStrandedTabs(TabStripModel* model) {
  std::vector<tabs::TabInterface*> stranded;
  for (int i = 0; i < model->IndexOfFirstNonPinnedTab(); ++i) {
    tabs::TabInterface* tab = model->GetTabAtIndex(i);
    if (IsKeptBesidePin(tab) && !tab->IsSplit()) {
      stranded.push_back(tab);
    }
  }
  for (tabs::TabInterface* tab : stranded) {
    SetBesidePin(tab->GetContents(), false);
    model->SetTabPinned(model->GetIndexOfTab(tab), false);
  }
}

bool IsAsPlanned(const TabStripModel& model, const SplitPlan& plan) {
  return IsPaired(model, plan.left, plan.right) &&
         (!plan.activate_left || model.GetActiveTab() == plan.left);
}

void KeepSplit(TabStripModel* model, const SplitPlan& plan) {
  if (!IsPaired(*model, plan.left, plan.right)) {
    Pair(model, plan.left, plan.right, plan.ratio);
  }
  if (plan.activate_left) {
    model->ActivateTabAt(model->GetIndexOfTab(plan.left));
  }
}

void ActivateBesideKeptTab(TabStripModel* model,
                           tabs::TabInterface* tab,
                           TabStripUserGestureDetails gesture) {
  if (CanBeLeft(tab)) {
    if (tabs::TabInterface* kept = KeptTab(*model)) {
      Pair(model, tab, kept, ShownRatio(*model));
    }
  }
  model->ActivateTabAt(model->GetIndexOfTab(tab), gesture);
}

void Split(TabStripModel* model,
           tabs::TabInterface* left,
           tabs::TabInterface* right) {
  if (left == right || IsKeptBesidePin(left) ||
      (right->IsPinned() && !IsKeptBesidePin(right))) {
    return;
  }
  Pair(model, left, right, ShownRatio(*model));
  tabs::TabInterface* active = model->GetActiveTab();
  if (active != left && active != right) {
    model->ActivateTabAt(model->GetIndexOfTab(left));
  }
}

void EndSplit(TabStripModel* model) {
  if (std::optional<split_tabs::SplitTabId> split = ShownSplit(*model)) {
    model->RemoveSplit(*split);
  }
}

void ReverseSplit(TabStripModel* model) {
  // A pin's tab stays on the left.
  if (std::optional<split_tabs::SplitTabId> split = ShownSplit(*model);
      split && !SplitTabs(*model, *split).front()->IsPinned()) {
    model->ReverseTabsInSplit(*split);
  }
}

void SetSplitRatio(TabStripModel* model, double ratio) {
  if (std::optional<split_tabs::SplitTabId> split = ShownSplit(*model)) {
    model->UpdateSplitRatio(*split, std::clamp(ratio, 0.0, 1.0),
                            /*is_intermediate=*/false);
  }
}

void MoveTab(TabStripModel* model,
             tabs::TabInterface* tab,
             tabs::TabInterface* before) {
  if (tab == before || tab->IsPinned()) {
    return;
  }
  std::optional<split_tabs::SplitTabId> split = tab->GetSplit();
  if (split && before && before->GetSplit() == split) {
    return;
  }
  int to = model->count();
  if (before) {
    // Before a split is before its first tab.
    std::optional<split_tabs::SplitTabId> before_split = before->GetSplit();
    to = model->GetIndexOfTab(
        before_split ? SplitTabs(*model, *before_split).front() : before);
  }
  if (!split) {
    const int from = model->GetIndexOfTab(tab);
    model->MoveWebContentsAt(from, to > from ? to - 1 : to,
                             /*select_after_move=*/false);
    return;
  }
  // Where its first tab goes once the split's out of the way.
  const int first = model->GetIndexOfTab(SplitTabs(*model, *split).front());
  const int count = static_cast<int>(SplitTabs(*model, *split).size());
  const int to_first = to > first ? to - count : to;
  if (to_first != first) {
    model->MoveSplitTo(*split, to_first, /*pinned=*/false, std::nullopt);
  }
}

}  // namespace fiber
