#include "fiber/browser/omnibox/fiber_omnibox_popup_view.h"

#import <Cocoa/Cocoa.h>

#include <algorithm>
#include <string>

#import "FiberBridge/FiberOmnibox.h"
#include "base/functional/bind.h"
#include "base/strings/sys_string_conversions.h"
#include "base/task/sequenced_task_runner.h"
#include "chrome/browser/ui/omnibox/omnibox_controller.h"
#include "chrome/browser/ui/omnibox/omnibox_popup_state_manager.h"
#include "components/bookmarks/browser/bookmark_model.h"
#include "components/omnibox/browser/actions/omnibox_action.h"
#include "components/omnibox/browser/autocomplete_controller.h"
#include "components/omnibox/browser/autocomplete_match.h"
#include "components/omnibox/browser/autocomplete_provider.h"
#include "components/omnibox/browser/autocomplete_result.h"
#include "components/omnibox/browser/omnibox_client.h"
#include "components/omnibox/browser/searchbox_utils.h"
#include "components/search_engines/template_url.h"
#include "components/search_engines/template_url_service.h"
#include "fiber/browser/favicons/favicon_image.h"
#include "ui/gfx/image/image.h"

namespace fiber {

namespace {

using MatchType = AutocompleteMatchType;

FiberSuggestionKind KindForMatch(const AutocompleteMatch& match,
                                 const OmniboxClient& client) {
  if (match.type == MatchType::NULL_RESULT_MESSAGE) {
    return FiberSuggestionKindMessage;
  }
  if (match.type == MatchType::PEDAL || match.IsToolbelt()) {
    return FiberSuggestionKindAction;
  }
  if (match.type == MatchType::CALCULATOR) {
    return FiberSuggestionKindCalculator;
  }
  // An extension's suggestions, through its omnibox keyword or otherwise.
  if (match.provider &&
      match.provider->type() == AutocompleteProvider::TYPE_UNSCOPED_EXTENSION) {
    return FiberSuggestionKindExtension;
  }
  const TemplateURLService* service = client.GetTemplateURLService();
  if (service && !match.keyword.empty()) {
    const TemplateURL* turl = service->GetTemplateURLForKeyword(match.keyword);
    if (turl && turl->type() == TemplateURL::OMNIBOX_API_EXTENSION) {
      return FiberSuggestionKindExtension;
    }
  }
  if (AutocompleteMatch::IsSearchHistoryType(match.type)) {
    return FiberSuggestionKindSearchHistory;
  }
  if (AutocompleteMatch::IsSearchType(match.type)) {
    return match.IsTrendSuggestion() ? FiberSuggestionKindTrendingSearch
                                     : FiberSuggestionKindSearch;
  }
  const bookmarks::BookmarkModel* bookmarks = client.GetBookmarkModel();
  if (bookmarks && bookmarks->IsBookmarked(match.destination_url)) {
    return FiberSuggestionKindBookmark;
  }
  return FiberSuggestionKindPage;
}

// Whether the suggestion shows its page's favicon, as in Chrome's popup.
bool ShowsFavicon(const AutocompleteMatch& match) {
  return !AutocompleteMatch::IsSearchType(match.type) &&
         !AutocompleteMatch::IsStarterPackType(match.type) &&
         match.type != MatchType::HISTORY_CLUSTER &&
         match.type != MatchType::NULL_RESULT_MESSAGE &&
         match.type != MatchType::PEDAL && match.destination_url.is_valid();
}

FiberTextStyle StyleFromClassification(int style) {
  FiberTextStyle result = FiberTextStyleNone;
  if (style & ACMatchClassification::URL) {
    result |= FiberTextStyleURL;
  }
  if (style & ACMatchClassification::MATCH) {
    result |= FiberTextStyleMatch;
  }
  if (style & ACMatchClassification::DIM) {
    result |= FiberTextStyleDim;
  }
  return result;
}

// Runs covering all of a `length`-long text, from its classifications (each
// styles the text from its offset to the next one's).
NSArray<FiberTextRun*>* RunsFromClassifications(
    const ACMatchClassifications& classifications,
    size_t length) {
  NSMutableArray<FiberTextRun*>* runs = [NSMutableArray array];
  auto add_run = [&](size_t start, size_t end, FiberTextStyle style) {
    if (start < end) {
      [runs addObject:[[FiberTextRun alloc]
                          initWithRange:NSMakeRange(start, end - start)
                                  style:style]];
    }
  };
  size_t unstyled_end = classifications.empty()
                            ? length
                            : std::min(classifications[0].offset, length);
  add_run(0, unstyled_end, FiberTextStyleNone);
  for (size_t i = 0; i < classifications.size(); ++i) {
    size_t start = std::min(classifications[i].offset, length);
    size_t end = i + 1 < classifications.size()
                     ? std::min(classifications[i + 1].offset, length)
                     : length;
    add_run(start, end, StyleFromClassification(classifications[i].style));
  }
  return runs;
}

FiberSuggestionPart PartFromLineState(OmniboxPopupSelection::LineState state) {
  switch (state) {
    case OmniboxPopupSelection::KEYWORD_MODE:
      return FiberSuggestionPartKeyword;
    case OmniboxPopupSelection::FOCUSED_BUTTON_ACTION:
      return FiberSuggestionPartAction;
    case OmniboxPopupSelection::FOCUSED_BUTTON_REMOVE_SUGGESTION:
      return FiberSuggestionPartRemove;
    default:
      return FiberSuggestionPartRow;
  }
}

}  // namespace

FiberOmniboxPopupView::FiberOmniboxPopupView(OmniboxController* controller,
                                             id<FiberOmnibox> ui)
    : OmniboxPopupView(controller), ui_(ui) {
  controller->edit_model()->set_popup_view(this);
  edit_model_observation_.Observe(controller->edit_model());
}

FiberOmniboxPopupView::~FiberOmniboxPopupView() {
  controller()->edit_model()->set_popup_view(nullptr);
}

bool FiberOmniboxPopupView::IsOpen() const {
  return is_open_;
}

void FiberOmniboxPopupView::InvalidateLine(size_t line) {
  if (is_open_) {
    UpdateSuggestions();
  }
}

void FiberOmniboxPopupView::UpdatePopupAppearance() {
  OmniboxPopupStateManager* state_manager = controller()->popup_state_manager();
  if (controller()->autocomplete_controller()->result().empty()) {
    if (is_open_) {
      is_open_ = false;
      [ui_ setSuggestions:@[]];
    }
    if (state_manager->popup_state() == OmniboxPopupState::kClassic) {
      state_manager->SetPopupState(OmniboxPopupState::kNone);
    }
    return;
  }
  is_open_ = true;
  state_manager->SetPopupState(OmniboxPopupState::kClassic);
  UpdateSuggestions();
}

void FiberOmniboxPopupView::ProvideButtonFocusHint(size_t line) {}

void FiberOmniboxPopupView::OnDragCanceled() {}

void FiberOmniboxPopupView::GetPopupAccessibleNodeData(
    ui::AXNodeData* node_data) const {}

bool FiberOmniboxPopupView::IsSelectionPopupControlled() const {
  // The edit model moves the selection; the palette only shows it.
  return false;
}

void FiberOmniboxPopupView::OnSelectionChanged(
    OmniboxPopupSelection old_selection,
    OmniboxPopupSelection new_selection) {
  if (is_open_) {
    UpdateSelection();
  }
}

void FiberOmniboxPopupView::OnMatchIconUpdated(size_t index) {
  InvalidateLine(index);
}

void FiberOmniboxPopupView::OnContentsChanged() {
  UpdatePopupAppearance();
}

void FiberOmniboxPopupView::OnCharTyped(base::TimeTicks timestamp) {}

void FiberOmniboxPopupView::UpdateSuggestions() {
  OmniboxClient& client = *controller()->client();
  const AutocompleteResult& result =
      controller()->autocomplete_controller()->result();
  NSMutableArray<FiberSuggestion*>* suggestions =
      [NSMutableArray arrayWithCapacity:result.size()];
  std::optional<omnibox::GroupId> previous_group;
  for (size_t i = 0; i < result.size(); ++i) {
    const AutocompleteMatch& original = result.match_at(i);
    // Page titles go first, as in Chrome's popup.
    const AutocompleteMatch match =
        original.GetMatchWithContentsAndDescriptionPossiblySwapped();

    NSImage* favicon = nil;
    if (ShowsFavicon(match)) {
      // Returns an empty image, and calls back later, when it isn't cached.
      gfx::Image image = client.GetFaviconForPageUrl(
          match.destination_url,
          base::BindOnce(&FiberOmniboxPopupView::OnFaviconFetched,
                         weak_ptr_factory_.GetWeakPtr()));
      if (!image.IsEmpty()) {
        favicon = FaviconImage(image, match.destination_url);
      }
    }

    std::u16string header;
    if (match.suggestion_group_id &&
        match.suggestion_group_id != previous_group) {
      header = result.GetHeaderForSuggestionGroup(*match.suggestion_group_id);
    }
    previous_group = match.suggestion_group_id;

    std::u16string keyword_label;
    if (!match.associated_keyword.empty()) {
      keyword_label =
          searchbox::GetKeywordLabelNames(match.associated_keyword,
                                          client.GetTemplateURLService())
              .full_name;
    }

    // Chrome doesn't show actions in keyword mode.
    NSMutableArray<NSString*>* action_titles = [NSMutableArray array];
    if (!match.from_keyword) {
      for (const auto& action : match.actions) {
        [action_titles
            addObject:base::SysUTF16ToNSString(action->GetLabelStrings().hint)];
      }
    }

    [suggestions
        addObject:[[FiberSuggestion alloc]
                      initWithKind:KindForMatch(match, client)
                          contents:base::SysUTF16ToNSString(match.contents)
                      contentsRuns:RunsFromClassifications(
                                       match.contents_class,
                                       match.contents.size())
                            detail:base::SysUTF16ToNSString(match.description)
                        detailRuns:RunsFromClassifications(
                                       match.description_class,
                                       match.description.size())
                           favicon:favicon
                            header:base::SysUTF16ToNSString(header)
                      keywordLabel:base::SysUTF16ToNSString(keyword_label)
                      actionTitles:action_titles
                         removable:match.SupportsDeletion()
                            hidden:controller()->IsSuggestionHidden(match)]];
  }
  [ui_ setSuggestions:suggestions];
  UpdateSelection();
}

void FiberOmniboxPopupView::UpdateSelection() {
  OmniboxPopupSelection selection =
      controller()->edit_model()->GetPopupSelection();
  NSInteger index = selection.line == OmniboxPopupSelection::kNoMatch
                        ? -1
                        : static_cast<NSInteger>(selection.line);
  [ui_ setSelectedSuggestionIndex:index
                             part:PartFromLineState(selection.state)
                      actionIndex:static_cast<NSInteger>(
                                      selection.action_index)];
}

void FiberOmniboxPopupView::OnFaviconFetched(const gfx::Image& favicon) {
  if (!is_open_ || is_favicon_update_posted_) {
    return;
  }
  is_favicon_update_posted_ = true;
  base::SequencedTaskRunner::GetCurrentDefault()->PostTask(
      FROM_HERE,
      base::BindOnce(&FiberOmniboxPopupView::UpdateForFetchedFavicons,
                     weak_ptr_factory_.GetWeakPtr()));
}

void FiberOmniboxPopupView::UpdateForFetchedFavicons() {
  is_favicon_update_posted_ = false;
  // They're cached now, for UpdateSuggestions() to find.
  if (is_open_) {
    UpdateSuggestions();
  }
}

}  // namespace fiber
