#include "fiber/browser/omnibox/fiber_omnibox_view.h"

#import <Cocoa/Cocoa.h>

#include <algorithm>

#import "FiberBridge/FiberOmnibox.h"
#include "base/memory/raw_ptr.h"
#include "base/strings/sys_string_conversions.h"
#include "base/time/time.h"
#include "chrome/browser/external_protocol/external_protocol_handler.h"
#include "chrome/browser/ui/omnibox/omnibox_controller.h"
#include "chrome/browser/ui/omnibox/omnibox_edit_model.h"
#include "components/omnibox/browser/omnibox_client.h"
#include "components/omnibox/browser/searchbox_utils.h"
#include "third_party/metrics_proto/omnibox_event.pb.h"
#import "ui/base/cocoa/cocoa_base_utils.h"

namespace {

// Where to open what was typed, from the modifier keys held with Return, as
// Chrome's omnibox decides: Option for a new tab, Command for one in the
// background, Shift for a new window.
WindowOpenDisposition DispositionFromReturn(NSEvent* event) {
  if (!event) {
    return WindowOpenDisposition::CURRENT_TAB;
  }
  NSEventModifierFlags flags = event.modifierFlags;
  return searchbox::ComputeOpenDispositionFromModifiersAndLogToUma(
      flags & NSEventModifierFlagShift, flags & NSEventModifierFlagControl,
      flags & NSEventModifierFlagOption, flags & NSEventModifierFlagCommand);
}

// Where to open a clicked suggestion, from the click's modifier keys and
// button, as for a link.
WindowOpenDisposition DispositionFromClick(NSEvent* event) {
  return event ? ui::WindowOpenDispositionFromNSEvent(event)
               : WindowOpenDisposition::CURRENT_TAB;
}

OmniboxPopupSelection::LineState LineStateFromPart(FiberSuggestionPart part) {
  switch (part) {
    case FiberSuggestionPartRow:
      return OmniboxPopupSelection::NORMAL;
    case FiberSuggestionPartKeyword:
      return OmniboxPopupSelection::KEYWORD_MODE;
    case FiberSuggestionPartAction:
      return OmniboxPopupSelection::FOCUSED_BUTTON_ACTION;
    case FiberSuggestionPartRemove:
      return OmniboxPopupSelection::FOCUSED_BUTTON_REMOVE_SUGGESTION;
  }
  return OmniboxPopupSelection::NORMAL;
}

// A range from the palette's field, clamped to its `length`.
gfx::Range RangeFromNSRange(NSRange range, size_t length) {
  size_t start = std::min<size_t>(range.location, length);
  size_t end = std::min<size_t>(start + range.length, length);
  return gfx::Range(start, end);
}

}  // namespace

// Carries out what the user does in the command palette on its
// FiberOmniboxView.
@interface FiberOmniboxViewActions : NSObject <FiberOmniboxActions>

- (instancetype)initWithOwner:(fiber::FiberOmniboxView*)owner;

// Called by the owner when it is being destroyed. Later calls do nothing.
- (void)detachOwner;

@end

@implementation FiberOmniboxViewActions {
  raw_ptr<fiber::FiberOmniboxView> _owner;
}

- (instancetype)initWithOwner:(fiber::FiberOmniboxView*)owner {
  if ((self = [super init])) {
    _owner = owner;
  }
  return self;
}

- (void)detachOwner {
  _owner = nullptr;
}

- (void)omniboxDidFocus {
  if (_owner) {
    _owner->OnFocus();
  }
}

- (void)omniboxDidBlur {
  if (_owner) {
    _owner->OnBlur();
  }
}

- (void)omniboxTextDidChange:(NSString*)text
               selectedRange:(NSRange)selectedRange
                   composing:(BOOL)composing {
  if (_owner) {
    std::u16string utf16 = base::SysNSStringToUTF16(text);
    _owner->OnTextChanged(utf16, RangeFromNSRange(selectedRange, utf16.size()),
                          composing);
  }
}

- (void)omniboxMoveSelection:(FiberSuggestionMove)move {
  if (!_owner) {
    return;
  }
  switch (move) {
    case FiberSuggestionMoveUp:
      _owner->OnUpOrDownPressed(/*down=*/false, /*page=*/false);
      break;
    case FiberSuggestionMoveDown:
      _owner->OnUpOrDownPressed(/*down=*/true, /*page=*/false);
      break;
    case FiberSuggestionMovePageUp:
      _owner->OnUpOrDownPressed(/*down=*/false, /*page=*/true);
      break;
    case FiberSuggestionMovePageDown:
      _owner->OnUpOrDownPressed(/*down=*/true, /*page=*/true);
      break;
    case FiberSuggestionMoveNext:
      _owner->OnTabPressed(/*shift=*/false);
      break;
    case FiberSuggestionMovePrevious:
      _owner->OnTabPressed(/*shift=*/true);
      break;
  }
}

- (void)omniboxOpenSelectionWithEvent:(NSEvent*)event {
  if (_owner) {
    _owner->OpenCurrentSelection(DispositionFromReturn(event));
  }
}

- (void)omniboxOpenSuggestionAtIndex:(NSInteger)index
                                part:(FiberSuggestionPart)part
                         actionIndex:(NSInteger)actionIndex
                               event:(NSEvent*)event {
  if (_owner && index >= 0 && actionIndex >= 0) {
    _owner->OpenSelection(
        OmniboxPopupSelection(static_cast<size_t>(index),
                              LineStateFromPart(part),
                              static_cast<size_t>(actionIndex)),
        DispositionFromClick(event));
  }
}

- (void)omniboxRemoveSuggestionAtIndex:(NSInteger)index {
  if (_owner && index >= 0) {
    _owner->RemoveSuggestion(static_cast<size_t>(index));
  }
}

- (void)omniboxClearKeyword {
  if (_owner) {
    _owner->ClearKeyword();
  }
}

@end

namespace fiber {

FiberOmniboxView::FiberOmniboxView(OmniboxController* controller,
                                   id<FiberOmnibox> ui)
    : OmniboxView(controller),
      ui_(ui),
      actions_([[FiberOmniboxViewActions alloc] initWithOwner:this]) {
  ui_.actions = actions_;
}

FiberOmniboxView::~FiberOmniboxView() {
  [actions_ detachOwner];
}

void FiberOmniboxView::OnTabChanged() {
  // Fiber doesn't keep a tab's unfinished edits (the palette closes when the
  // tab changes), so there's no saved state to restore.
  edit_model()->RestoreState(nullptr);
}

void FiberOmniboxView::UpdateUI() {
  [ui_ setText:base::SysUTF16ToNSString(text_)
      selectedRange:selection_.ToNSRange()];
  std::u16string keyword_label;
  if (edit_model()->is_keyword_selected()) {
    keyword_label = searchbox::GetKeywordLabelNames(
                        edit_model()->keyword(),
                        controller()->client()->GetTemplateURLService())
                        .full_name;
  }
  [ui_ setKeywordLabel:base::SysUTF16ToNSString(keyword_label)];
}

void FiberOmniboxView::OnFocus() {
  if (has_focus_) {
    return;
  }
  has_focus_ = true;
  edit_model()->OnSetFocus(/*control_down=*/false);
  // The page's full URL, all selected, rather than the short form that Chrome
  // shows until the user edits it.
  if (!edit_model()->Unelide()) {
    SelectAll(/*reversed=*/true);
  }
  // Suggestions before the user types, like recent searches.
  edit_model()->StartZeroSuggestRequest();
  UpdateUI();
}

void FiberOmniboxView::OnBlur() {
  if (!has_focus_) {
    return;
  }
  has_focus_ = false;
  edit_model()->OnWillKillFocus();
  edit_model()->OnKillFocus();
  // The palette is gone, and what the user typed with it.
  RevertAll();
}

void FiberOmniboxView::OnTextChanged(const std::u16string& text,
                                     const gfx::Range& selection,
                                     bool composing) {
  OnBeforePossibleChange();
  text_ = text;
  selection_ = selection;
  composing_ = composing;
  OnAfterPossibleChange(/*allow_keyword_ui_change=*/true);
}

void FiberOmniboxView::OnUpOrDownPressed(bool down, bool page) {
  edit_model()->OnUpOrDownPressed(down, page);
}

void FiberOmniboxView::OnTabPressed(bool shift) {
  if (controller()->IsPopupOpen()) {
    edit_model()->OnTabPressed(shift);
  }
}

void FiberOmniboxView::OpenCurrentSelection(WindowOpenDisposition disposition) {
  // A user gesture, so the page may open an external app (e.g. a mailto: URL).
  ExternalProtocolHandler::PermitLaunchUrl();
  edit_model()->OpenCurrentSelection(base::TimeTicks::Now(), disposition,
                                     /*via_keyboard=*/true);
}

void FiberOmniboxView::OpenSelection(OmniboxPopupSelection selection,
                                     WindowOpenDisposition disposition) {
  if (selection.state == OmniboxPopupSelection::KEYWORD_MODE) {
    // The keyword button doesn't open anything: it starts keyword mode.
    edit_model()->SetPopupSelection(selection);
    edit_model()->AcceptKeyword(metrics::OmniboxEventProto::CLICK_HINT_VIEW);
    return;
  }
  ExternalProtocolHandler::PermitLaunchUrl();
  edit_model()->OpenSelection(selection, base::TimeTicks::Now(), disposition,
                              /*via_keyboard=*/false);
}

void FiberOmniboxView::RemoveSuggestion(size_t line) {
  if (controller()->IsPopupOpen()) {
    edit_model()->TryDeletingPopupLine(line);
  }
}

void FiberOmniboxView::ClearKeyword() {
  if (edit_model()->is_keyword_selected()) {
    edit_model()->ClearKeyword();
  }
}

// OmniboxView:

void FiberOmniboxView::Update() {
  // As OmniboxViewViews does: show the page's new URL, unless the user is
  // editing.
  if (edit_model()->ResetDisplayTexts()) {
    RevertAll();
    if (edit_model()->has_focus()) {
      SelectAll(/*reversed=*/true);
    }
  }
}

std::u16string FiberOmniboxView::GetText() const {
  return text_;
}

void FiberOmniboxView::SetWindowTextAndCaretPos(const std::u16string& text,
                                                size_t caret_pos,
                                                bool update_popup,
                                                bool notify_text_changed) {
  text_ = text;
  selection_ = gfx::Range(std::min(caret_pos, text_.size()));
  if (update_popup) {
    UpdatePopup();
  }
  if (notify_text_changed) {
    TextChanged();
  }
  UpdateUI();
}

void FiberOmniboxView::SetCaretPos(size_t caret_pos) {
  selection_ = gfx::Range(std::min(caret_pos, text_.size()));
  UpdateUI();
}

void FiberOmniboxView::SetAdditionalText(const std::u16string& text) {
  // Chrome shows this beside the field, e.g. the URL of a suggestion
  // autocompleted from its title. The palette doesn't.
}

void FiberOmniboxView::EnterKeywordModeForDefaultSearchProvider() {
  edit_model()->EnterKeywordModeForDefaultSearchProvider(
      metrics::OmniboxEventProto::KEYBOARD_SHORTCUT);
  UpdateUI();
}

bool FiberOmniboxView::IsSelectAll() const {
  return !text_.empty() && selection_.GetMin() == 0 &&
         selection_.GetMax() == text_.size();
}

gfx::Range FiberOmniboxView::GetSelectionBounds() const {
  return selection_;
}

void FiberOmniboxView::SetSelectionBounds(gfx::Range selection) {
  selection_ = gfx::Range(std::min<size_t>(selection.start(), text_.size()),
                          std::min<size_t>(selection.end(), text_.size()));
  UpdateUI();
}

bool FiberOmniboxView::HasSelection() const {
  return !selection_.is_empty();
}

void FiberOmniboxView::SelectAll(bool reversed) {
  selection_ =
      reversed ? gfx::Range(text_.size(), 0) : gfx::Range(0, text_.size());
  UpdateUI();
}

void FiberOmniboxView::RevertAll() {
  OmniboxView::RevertAll();
  // Clearing the results closes the suggestions, as Chrome's
  // OmniboxPopupCloser does for its views omnibox.
  controller()->StopAutocomplete(/*clear_result=*/true);
  UpdateUI();
}

void FiberOmniboxView::UpdatePopup() {
  // Inline autocompletion only when the caret is at the end, and not while an
  // input method is composing.
  edit_model()->UpdateInput(
      /*prevent_inline_autocomplete=*/composing_ ||
      selection_.GetMin() != text_.size());
}

void FiberOmniboxView::SetFocus(bool is_user_initiated) {
  [ui_ focus];
  // As Chrome does: if Control is down (e.g. Control-L), it isn't also taken
  // for Control-Return.
  edit_model()->ConsumeCtrlKey();
}

bool FiberOmniboxView::AimButtonVisible() const {
  return false;
}

void FiberOmniboxView::ApplyCaretVisibility() {}

void FiberOmniboxView::OnTemporaryTextMaybeChanged(
    const std::u16string& display_text,
    const AutocompleteMatch& match,
    bool save_original_selection,
    bool notify_text_changed) {
  if (save_original_selection) {
    saved_selection_for_temporary_text_ = selection_;
  }
  SetWindowTextAndCaretPos(display_text, display_text.size(),
                           /*update_popup=*/false, notify_text_changed);
}

void FiberOmniboxView::OnInlineAutocompleteTextMaybeChanged(
    const std::u16string& user_text,
    const std::u16string& inline_autocompletion) {
  std::u16string display_text = user_text + inline_autocompletion;
  if (display_text == text_ || composing_) {
    return;
  }
  // The completion is selected, so typing replaces it.
  text_ = display_text;
  selection_ = gfx::Range(display_text.size(), user_text.size());
  UpdateUI();
}

void FiberOmniboxView::OnInlineAutocompleteTextCleared() {}

void FiberOmniboxView::OnRevertTemporaryText(const std::u16string& display_text,
                                             const AutocompleteMatch& match) {
  // The model has already put the text back.
  selection_ = saved_selection_for_temporary_text_;
  UpdateUI();
}

void FiberOmniboxView::OnBeforePossibleChange() {
  state_before_change_ = GetState();
  composing_before_change_ = composing_;
}

bool FiberOmniboxView::OnAfterPossibleChange(bool allow_keyword_ui_change) {
  // `state_changes` points into both states, so this one has to outlive it.
  State new_state = GetState();
  StateChanges state_changes = GetStateChanges(state_before_change_, new_state);
  // Starting or finishing a composition counts as a change, as it does for
  // OmniboxViewViews: it decides whether to autocomplete inline.
  state_changes.text_differs =
      state_changes.text_differs || composing_before_change_ != composing_;
  bool something_changed = edit_model()->OnAfterPossibleChange(
      state_changes, allow_keyword_ui_change && !composing_);
  if (something_changed &&
      (state_changes.text_differs || state_changes.keyword_differs)) {
    TextChanged();
  }
  UpdateUI();
  return something_changed;
}

void FiberOmniboxView::OnKeywordPlaceholderTextChange() {
  UpdateUI();
}

int FiberOmniboxView::GetOmniboxTextLength() const {
  return static_cast<int>(text_.size());
}

// The palette's field doesn't style URLs, so these have nothing to do.

void FiberOmniboxView::EmphasizeURLComponents() {}

void FiberOmniboxView::SetEmphasis(bool emphasize, const gfx::Range& range) {}

void FiberOmniboxView::UpdateSchemeStyle(const gfx::Range& range) {}

OmniboxEditModel* FiberOmniboxView::edit_model() {
  return controller()->edit_model();
}

}  // namespace fiber
