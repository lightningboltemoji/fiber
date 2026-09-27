#ifndef FIBER_BROWSER_OMNIBOX_FIBER_OMNIBOX_VIEW_H_
#define FIBER_BROWSER_OMNIBOX_FIBER_OMNIBOX_VIEW_H_

#include <string>

#include "chrome/browser/ui/omnibox/omnibox_view.h"
#include "components/omnibox/browser/omnibox_popup_selection.h"
#include "ui/base/window_open_disposition.h"
#include "ui/gfx/range/range.h"

@class FiberOmniboxViewActions;
@protocol FiberOmnibox;

namespace fiber {

// Chrome's omnibox, with Fiber's command palette as its text field. Chrome's
// OmniboxEditModel decides what the field shows (the page's URL, what the user
// typed, inline autocompletion, the selected suggestion's text) and this
// mirrors that to the palette (a FiberOmnibox). What the user does in the
// palette comes back through its FiberOmniboxActions.
//
// Like Chrome's views omnibox (OmniboxViewViews), `text_` is everything in the
// field, inline autocompletion included, which the field shows selected.
class FiberOmniboxView : public OmniboxView {
 public:
  // `controller` must outlive this.
  FiberOmniboxView(OmniboxController* controller, id<FiberOmnibox> ui);
  FiberOmniboxView(const FiberOmniboxView&) = delete;
  FiberOmniboxView& operator=(const FiberOmniboxView&) = delete;
  ~FiberOmniboxView() override;

  // The active tab changed: show its URL, and drop any editing.
  void OnTabChanged();
  // Sends the palette what its field shows.
  void UpdateUI();

  // What the user does in the palette:
  void OnFocus();
  void OnBlur();
  void OnTextChanged(const std::u16string& text,
                     const gfx::Range& selection,
                     bool composing);
  void OnUpOrDownPressed(bool down, bool page);
  void OnTabPressed(bool shift);
  void OpenCurrentSelection(WindowOpenDisposition disposition);
  void OpenSelection(OmniboxPopupSelection selection,
                     WindowOpenDisposition disposition);
  void RemoveSuggestion(size_t line);
  void ClearKeyword();

  // OmniboxView:
  void Update() override;
  std::u16string GetText() const override;
  void SetWindowTextAndCaretPos(const std::u16string& text,
                                size_t caret_pos,
                                bool update_popup,
                                bool notify_text_changed) override;
  void SetCaretPos(size_t caret_pos) override;
  void SetAdditionalText(const std::u16string& text) override;
  void EnterKeywordModeForDefaultSearchProvider() override;
  bool IsSelectAll() const override;
  gfx::Range GetSelectionBounds() const override;
  void SetSelectionBounds(gfx::Range selection) override;
  bool HasSelection() const override;
  void SelectAll(bool reversed) override;
  void RevertAll() override;
  void UpdatePopup() override;
  void SetFocus(bool is_user_initiated) override;
  bool AimButtonVisible() const override;
  void ApplyCaretVisibility() override;
  void OnTemporaryTextMaybeChanged(const std::u16string& display_text,
                                   const AutocompleteMatch& match,
                                   bool save_original_selection,
                                   bool notify_text_changed) override;
  void OnInlineAutocompleteTextMaybeChanged(
      const std::u16string& user_text,
      const std::u16string& inline_autocompletion) override;
  void OnInlineAutocompleteTextCleared() override;
  void OnRevertTemporaryText(const std::u16string& display_text,
                             const AutocompleteMatch& match) override;
  void OnBeforePossibleChange() override;
  bool OnAfterPossibleChange(bool allow_keyword_ui_change) override;
  void OnKeywordPlaceholderTextChange() override;
  int GetOmniboxTextLength() const override;
  void EmphasizeURLComponents() override;
  void SetEmphasis(bool emphasize, const gfx::Range& range) override;
  void UpdateSchemeStyle(const gfx::Range& range) override;

 private:
  OmniboxEditModel* edit_model();

  id<FiberOmnibox> __weak ui_;
  FiberOmniboxViewActions* __strong actions_;

  std::u16string text_;
  gfx::Range selection_;
  // Whether an input method is composing text in the field. Inline
  // autocompletion waits until it's done.
  bool composing_ = false;
  bool has_focus_ = false;

  // The selection to go back to when the user reverts the text of an arrowed-to
  // suggestion.
  gfx::Range saved_selection_for_temporary_text_;
  // As of OnBeforePossibleChange(), for OnAfterPossibleChange() to compare.
  State state_before_change_;
  bool composing_before_change_ = false;
};

}  // namespace fiber

#endif  // FIBER_BROWSER_OMNIBOX_FIBER_OMNIBOX_VIEW_H_
