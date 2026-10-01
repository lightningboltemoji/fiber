#include "fiber/browser/find_bar/fiber_find_bar.h"

#import <Cocoa/Cocoa.h>

#include <algorithm>

#import "FiberBridge/FiberFindBar.h"
#include "base/memory/raw_ptr.h"
#include "base/strings/sys_string_conversions.h"
#include "chrome/browser/enterprise/data_protection/data_protection_clipboard_utils.h"
#include "chrome/browser/ui/find_bar/find_bar_controller.h"
#include "components/find_in_page/find_notification_details.h"
#include "components/find_in_page/find_tab_helper.h"
#include "components/find_in_page/find_types.h"
#include "content/public/browser/web_contents.h"
#include "fiber/browser/window/fiber_browser_window.h"
#include "ui/gfx/range/range.h"

// Carries out what the user does in the find bar on its FiberFindBar.
@interface FiberFindBarActionsBridge : NSObject <FiberFindBarActions>

- (instancetype)initWithOwner:(fiber::FiberFindBar*)owner;

// Called by the owner when it is being destroyed. Later calls do nothing.
- (void)detachOwner;

@end

@implementation FiberFindBarActionsBridge {
  raw_ptr<fiber::FiberFindBar> _owner;
}

- (instancetype)initWithOwner:(fiber::FiberFindBar*)owner {
  if ((self = [super init])) {
    _owner = owner;
  }
  return self;
}

- (void)detachOwner {
  _owner = nullptr;
}

- (void)findBarTextDidChange:(NSString*)text {
  if (_owner) {
    _owner->OnTextChanged(base::SysNSStringToUTF16(text));
  }
}

- (void)findBarFindNext {
  if (_owner) {
    _owner->FindNext(/*forward=*/true);
  }
}

- (void)findBarFindPrevious {
  if (_owner) {
    _owner->FindNext(/*forward=*/false);
  }
}

- (void)findBarClose {
  if (_owner) {
    _owner->Close();
  }
}

- (void)findBarFocusDidChange:(BOOL)focused {
  if (_owner) {
    _owner->OnFocusChanged(focused);
  }
}

@end

namespace fiber {

FiberFindBar::FiberFindBar(FiberBrowserWindow* window, id<FiberFindBar> ui)
    : window_(window),
      ui_(ui),
      actions_([[FiberFindBarActionsBridge alloc] initWithOwner:this]) {
  ui_.actions = actions_;
}

FiberFindBar::~FiberFindBar() {
  [actions_ detachOwner];
}

void FiberFindBar::OnTextChanged(const std::u16string& text) {
  content::WebContents* contents = GetWebContents();
  if (!contents) {
    return;
  }
  controller_->OnUserChangedFindText(text);
  find_in_page::FindTabHelper::FromWebContents(contents)->StartFinding(
      text, /*forward_direction=*/true, /*case_sensitive=*/false,
      /*find_match=*/true);
}

void FiberFindBar::FindNext(bool forward) {
  content::WebContents* contents = GetWebContents();
  std::u16string text(GetFindText());
  if (!contents || text.empty()) {
    return;
  }
  find_in_page::FindTabHelper::FromWebContents(contents)->StartFinding(
      text, forward, /*case_sensitive=*/false, /*find_match=*/true);
}

void FiberFindBar::Close() {
  if (controller_) {
    controller_->EndFindSession(find_in_page::SelectionAction::kKeep,
                                find_in_page::ResultAction::kKeep);
  }
}

void FiberFindBar::OnFocusChanged(bool focused) {
  SetFocusedOnCurrentTab(focused);
}

FindBarController* FiberFindBar::GetFindBarController() const {
  return controller_;
}

void FiberFindBar::SetFindBarController(FindBarController* find_bar_controller) {
  controller_ = find_bar_controller;
}

void FiberFindBar::Show(bool animate, bool focus) {
  [ui_ showAnimated:animate focus:focus];
  SetVisible(true);
}

void FiberFindBar::Hide(bool animate) {
  // The keyboard doesn't stay in a field that's going.
  if (HasFocus()) {
    window_->FocusWebContents();
  }
  [ui_ hideAnimated:animate];
  SetVisible(false);
}

void FiberFindBar::SetFocusAndSelection() {
  [ui_ focusAndSelectAll];
  SetFocusedOnCurrentTab(true);
}

void FiberFindBar::ClearResults(
    const find_in_page::FindNotificationDetails& results) {
  [ui_ setMatchCount:-1 activeMatch:0];
}

void FiberFindBar::StopAnimation() {}

void FiberFindBar::MoveWindowIfNecessary() {}

void FiberFindBar::SetFindTextAndSelectedRange(
    const std::u16string& find_text,
    const gfx::Range& selected_range) {
  [ui_ setText:base::SysUTF16ToNSString(find_text)
      selectedRange:selected_range.IsValid()
                        ? NSMakeRange(selected_range.GetMin(),
                                      selected_range.length())
                        : NSMakeRange(0, 0)];
}

std::u16string_view FiberFindBar::GetFindText() const {
  find_text_ = base::SysNSStringToUTF16(ui_.text);
  return find_text_;
}

gfx::Range FiberFindBar::GetSelectedRange() const {
  const NSRange range = ui_ ? ui_.selectedRange : NSMakeRange(0, 0);
  return gfx::Range(range.location, NSMaxRange(range));
}

void FiberFindBar::UpdateUIForFindResult(
    const find_in_page::FindNotificationDetails& result,
    const std::u16string& find_text) {
  // The controller watches the tab's finds even while the bar is closed, and
  // the command palette finds with the same FindTabHelper.
  content::WebContents* contents = GetWebContents();
  if (!contents ||
      !find_in_page::FindTabHelper::FromWebContents(contents)
           ->find_ui_active()) {
    return;
  }
  if (find_text.empty()) {
    [ui_ setMatchCount:-1 activeMatch:0];
    return;
  }
  NSString* text = base::SysUTF16ToNSString(find_text);
  if (![ui_.text isEqualToString:text]) {
    [ui_ setText:text selectedRange:NSMakeRange(0, text.length)];
  }
  int count = result.number_of_matches();
  const int active_match = result.active_match_ordinal();
  // No matches yet may only mean the page isn't done counting.
  if (active_match == -1 || (count == 0 && !result.final_update())) {
    count = -1;
  }
  [ui_ setMatchCount:count activeMatch:std::max(active_match, 0)];
}

void FiberFindBar::AudibleAlert() {}

bool FiberFindBar::IsFindBarVisible() const {
  return visible_;
}

void FiberFindBar::RestoreSavedFocus() {
  SetFocusedOnCurrentTab(false);
  // Only from the bar: whatever else has the keyboard (the omnibar, say)
  // keeps it, though Chrome calls this as a navigation closes the bar.
  if (HasFocus()) {
    window_->FocusWebContents();
  }
}

bool FiberFindBar::HasGlobalFindPasteboard() const {
  return true;
}

void FiberFindBar::UpdateFindBarForChangedWebContents() {}

bool FiberFindBar::CanPopulateFromSelectedText() {
  content::WebContents* contents = GetWebContents();
  return !contents ||
         enterprise_data_protection::CanPopulateFindBarFromSelection(contents);
}

const FindBarTesting* FiberFindBar::GetFindBarTesting() const {
  return nullptr;
}

bool FiberFindBar::HasFocus() const {
  return ui_.hasFocus;
}

void FiberFindBar::CloseOverlappingBubbles() {}

views::Widget* FiberFindBar::GetHostWidget() {
  return nullptr;
}

content::WebContents* FiberFindBar::GetWebContents() const {
  return controller_ ? controller_->web_contents() : nullptr;
}

void FiberFindBar::SetVisible(bool visible) {
  if (visible_ == visible) {
    return;
  }
  visible_ = visible;
  // For the commands that depend on it, like IDC_CLOSE_FIND_OR_STOP.
  if (controller_) {
    controller_->OnFindBarVisibilityChanged();
  }
}

void FiberFindBar::SetFocusedOnCurrentTab(bool focused) {
  if (content::WebContents* contents = GetWebContents()) {
    find_in_page::FindTabHelper::FromWebContents(contents)
        ->set_find_ui_focused(focused);
  }
}

}  // namespace fiber
