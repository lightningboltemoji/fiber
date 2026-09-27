#ifndef FIBER_BROWSER_WINDOW_FIBER_LOCATION_BAR_H_
#define FIBER_BROWSER_WINDOW_FIBER_LOCATION_BAR_H_

#include <memory>

#include "base/memory/raw_ptr.h"
#include "chrome/browser/ui/location_bar/location_bar.h"

@protocol FiberOmnibox;
class OmniboxController;

namespace fiber {

class FiberBrowserWindow;
class FiberOmniboxPopupView;
class FiberOmniboxView;

// The window's LocationBar: Chrome's omnibox (OmniboxController, with its
// ChromeOmniboxClient), drawn by Fiber's command palette. It stubs the
// views-specific rest (chips, bubble anchors, layout).
class FiberLocationBar : public LocationBar {
 public:
  // `omnibox` is the window's command palette.
  FiberLocationBar(FiberBrowserWindow* window, id<FiberOmnibox> omnibox);
  FiberLocationBar(const FiberLocationBar&) = delete;
  FiberLocationBar& operator=(const FiberLocationBar&) = delete;
  ~FiberLocationBar() override;

  // LocationBar:
  void FocusLocation(bool is_user_initiated,
                     bool clear_focus_if_failed) override;
  void FocusSearch() override;
  void UpdateFocusBehavior(bool toolbar_visible) override;
  void UpdateContentSettingsIcons() override;
  void SaveStateToContents(content::WebContents* contents) override;
  void Revert() override;
  OmniboxView* GetOmniboxView() override;
  OmniboxPopupView* GetOmniboxPopupView() override;
  OmniboxController* GetOmniboxController() override;
  bool ShouldCloseOmniboxPopup(ui::MouseEvent* event) override;
  content::WebContents* GetWebContents() override;
  LocationBarModel* GetLocationBarModel() override;
  std::optional<bubble_anchor_util::AnchorConfiguration> GetChipAnchor()
      override;
  ChipController* GetChipController() override;
  void AnnounceAlert(const std::u16string& announcement) override;
  void OnChanged() override;
  void UpdateWithoutTabRestore() override;
  ui::TrackedElement* GetAnchorOrNull() override;
  BrowserWindowInterface* GetBrowser() override;
  Profile* GetProfile() override;
  bool IsInitialized() const override;
  bool IsVisible() const override;
  bool IsDrawn() const override;
  bool IsFullscreen() const override;
  bool IsEditingOrEmpty() const override;
  bool IsMouseHovered() const override;
  bool IsFocusWithin() const override;
  void InvalidateLayout() override;
  gfx::Rect Bounds() const override;
  gfx::Rect BoundsInScreen() const override;
  gfx::Size MinimumSize() const override;
  gfx::Size PreferredSize() const override;
  void Update(content::WebContents* contents) override;
  void ResetTabState(content::WebContents* contents) override;
  bool HasSecurityStateChanged() override;
  LocationBarTesting* GetLocationBarForTesting() override;

 private:
  const raw_ptr<FiberBrowserWindow> window_;
  // Outlives the view and popup view, which refer to it.
  std::unique_ptr<OmniboxController> omnibox_controller_;
  std::unique_ptr<FiberOmniboxView> omnibox_view_;
  std::unique_ptr<FiberOmniboxPopupView> omnibox_popup_view_;
};

}  // namespace fiber

#endif  // FIBER_BROWSER_WINDOW_FIBER_LOCATION_BAR_H_
