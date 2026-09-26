#include "fiber/browser/window/fiber_location_bar.h"

#include "chrome/browser/ui/browser_command_controller.h"
#include "chrome/browser/ui/browser_window/public/browser_window_features.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#include "chrome/browser/ui/tabs/tab_strip_model.h"
#include "chrome/browser/ui/views/bubble_anchor_util_views.h"
#include "fiber/browser/window/fiber_browser_window.h"
#include "ui/gfx/geometry/rect.h"
#include "ui/gfx/geometry/size.h"

namespace fiber {

FiberLocationBar::FiberLocationBar(FiberBrowserWindow* window)
    : LocationBar(chrome::BrowserCommandController::From(window->browser())),
      window_(window) {}

FiberLocationBar::~FiberLocationBar() = default;

void FiberLocationBar::FocusLocation(bool is_user_initiated,
                                     bool clear_focus_if_failed) {
  window_->SetFocusToLocationBar(is_user_initiated);
}

void FiberLocationBar::FocusSearch() {
  window_->SetFocusToLocationBar(/*is_user_initiated=*/true);
}

void FiberLocationBar::UpdateFocusBehavior(bool toolbar_visible) {}

void FiberLocationBar::UpdateContentSettingsIcons() {}

void FiberLocationBar::SaveStateToContents(content::WebContents* contents) {}

void FiberLocationBar::Revert() {
  window_->UpdateToolbar(nullptr);
}

OmniboxView* FiberLocationBar::GetOmniboxView() {
  return nullptr;
}

OmniboxPopupView* FiberLocationBar::GetOmniboxPopupView() {
  return nullptr;
}

OmniboxController* FiberLocationBar::GetOmniboxController() {
  return nullptr;
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

void FiberLocationBar::OnChanged() {}

void FiberLocationBar::UpdateWithoutTabRestore() {
  window_->UpdateToolbar(nullptr);
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
  return false;
}

bool FiberLocationBar::IsMouseHovered() const {
  return false;
}

bool FiberLocationBar::IsFocusWithin() const {
  return false;
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
  window_->UpdateToolbar(contents);
}

void FiberLocationBar::ResetTabState(content::WebContents* contents) {}

bool FiberLocationBar::HasSecurityStateChanged() {
  return false;
}

LocationBarTesting* FiberLocationBar::GetLocationBarForTesting() {
  return nullptr;
}

}  // namespace fiber
