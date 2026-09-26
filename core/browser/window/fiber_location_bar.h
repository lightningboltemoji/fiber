#ifndef FIBER_BROWSER_WINDOW_FIBER_LOCATION_BAR_H_
#define FIBER_BROWSER_WINDOW_FIBER_LOCATION_BAR_H_

#include "base/memory/raw_ptr.h"
#include "chrome/browser/ui/location_bar/location_bar.h"

namespace fiber {

class FiberBrowserWindow;

// Chrome's code expects every browser window to have a LocationBar. Fiber's
// address field is in its own UI (//fiber/ui), so this forwards the calls that
// matter to the window and stubs the omnibox- and views-specific rest.
class FiberLocationBar : public LocationBar {
 public:
  explicit FiberLocationBar(FiberBrowserWindow* window);
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
};

}  // namespace fiber

#endif  // FIBER_BROWSER_WINDOW_FIBER_LOCATION_BAR_H_
