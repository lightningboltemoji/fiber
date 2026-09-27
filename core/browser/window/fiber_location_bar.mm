#include "fiber/browser/window/fiber_location_bar.h"

#include "chrome/browser/ui/browser_command_controller.h"
#include "chrome/browser/ui/browser_window/public/browser_window_features.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#include "chrome/browser/ui/omnibox/chrome_omnibox_client.h"
#include "chrome/browser/ui/omnibox/omnibox_controller.h"
#include "chrome/browser/ui/tabs/tab_strip_model.h"
#include "chrome/browser/ui/views/bubble_anchor_util_views.h"
#include "fiber/browser/omnibox/fiber_omnibox_popup_view.h"
#include "fiber/browser/omnibox/fiber_omnibox_view.h"
#include "fiber/browser/window/fiber_browser_window.h"
#include "ui/gfx/geometry/rect.h"
#include "ui/gfx/geometry/size.h"

namespace fiber {

FiberLocationBar::FiberLocationBar(FiberBrowserWindow* window,
                                   id<FiberOmnibox> omnibox)
    : LocationBar(chrome::BrowserCommandController::From(window->browser())),
      window_(window) {
  omnibox_controller_ =
      std::make_unique<OmniboxController>(std::make_unique<ChromeOmniboxClient>(
          /*location_bar=*/this, window->browser(),
          window->browser()->GetProfile()));
  omnibox_view_ =
      std::make_unique<FiberOmniboxView>(omnibox_controller_.get(), omnibox);
  omnibox_popup_view_ = std::make_unique<FiberOmniboxPopupView>(
      omnibox_controller_.get(), omnibox);
}

FiberLocationBar::~FiberLocationBar() {
  // The views first: they refer to the controller.
  omnibox_popup_view_.reset();
  omnibox_view_.reset();
  omnibox_controller_.reset();
}

void FiberLocationBar::FocusLocation(bool is_user_initiated,
                                     bool clear_focus_if_failed) {
  omnibox_view_->SetFocus(is_user_initiated);
}

void FiberLocationBar::FocusSearch() {
  omnibox_view_->SetFocus(/*is_user_initiated=*/true);
}

void FiberLocationBar::UpdateFocusBehavior(bool toolbar_visible) {}

void FiberLocationBar::UpdateContentSettingsIcons() {}

void FiberLocationBar::SaveStateToContents(content::WebContents* contents) {
  // Nothing to save: the palette closes when the tab changes, and closing it
  // discards the edit.
}

void FiberLocationBar::Revert() {
  omnibox_view_->RevertAll();
}

OmniboxView* FiberLocationBar::GetOmniboxView() {
  return omnibox_view_.get();
}

OmniboxPopupView* FiberLocationBar::GetOmniboxPopupView() {
  return omnibox_popup_view_.get();
}

OmniboxController* FiberLocationBar::GetOmniboxController() {
  return omnibox_controller_.get();
}

bool FiberLocationBar::ShouldCloseOmniboxPopup(ui::MouseEvent* event) {
  return false;
}

content::WebContents* FiberLocationBar::GetWebContents() {
  return GetBrowser()->GetTabStripModel()->GetActiveWebContents();
}

LocationBarModel* FiberLocationBar::GetLocationBarModel() {
  return GetBrowser()->GetFeatures().location_bar_model();
}

std::optional<bubble_anchor_util::AnchorConfiguration>
FiberLocationBar::GetChipAnchor() {
  return std::nullopt;
}

ChipController* FiberLocationBar::GetChipController() {
  return nullptr;
}

void FiberLocationBar::AnnounceAlert(const std::u16string& announcement) {}

void FiberLocationBar::OnChanged() {
  // The omnibox's state changed, e.g. into keyword mode. (Not while it's
  // being torn down.)
  if (omnibox_view_) {
    omnibox_view_->UpdateUI();
  }
}

void FiberLocationBar::UpdateWithoutTabRestore() {
  Update(nullptr);
}

ui::TrackedElement* FiberLocationBar::GetAnchorOrNull() {
  return nullptr;
}

BrowserWindowInterface* FiberLocationBar::GetBrowser() {
  return window_->browser();
}

Profile* FiberLocationBar::GetProfile() {
  return GetBrowser()->GetProfile();
}

bool FiberLocationBar::IsInitialized() const {
  return true;
}

bool FiberLocationBar::IsVisible() const {
  return true;
}

bool FiberLocationBar::IsDrawn() const {
  return true;
}

bool FiberLocationBar::IsFullscreen() const {
  return false;
}

bool FiberLocationBar::IsEditingOrEmpty() const {
  return omnibox_view_->IsEditingOrEmpty();
}

bool FiberLocationBar::IsMouseHovered() const {
  return false;
}

bool FiberLocationBar::IsFocusWithin() const {
  return omnibox_controller_->edit_model()->has_focus();
}

void FiberLocationBar::InvalidateLayout() {}

gfx::Rect FiberLocationBar::Bounds() const {
  return gfx::Rect();
}

gfx::Rect FiberLocationBar::BoundsInScreen() const {
  return gfx::Rect();
}

gfx::Size FiberLocationBar::MinimumSize() const {
  return gfx::Size();
}

gfx::Size FiberLocationBar::PreferredSize() const {
  return gfx::Size();
}

void FiberLocationBar::Update(content::WebContents* contents) {
  if (!omnibox_view_) {
    return;
  }
  // A new tab to show (`contents`), or the current one changed.
  if (contents) {
    omnibox_view_->OnTabChanged();
  } else {
    omnibox_view_->Update();
  }
  window_->UpdatePageState();
}

void FiberLocationBar::ResetTabState(content::WebContents* contents) {}

bool FiberLocationBar::HasSecurityStateChanged() {
  return false;
}

LocationBarTesting* FiberLocationBar::GetLocationBarForTesting() {
  return nullptr;
}

}  // namespace fiber
