#ifndef FIBER_BROWSER_FIND_BAR_FIBER_FIND_BAR_H_
#define FIBER_BROWSER_FIND_BAR_FIBER_FIND_BAR_H_

#include <string>
#include <string_view>

#include "base/memory/raw_ptr.h"
#include "chrome/browser/ui/find_bar/find_bar.h"

@class FiberFindBarActionsBridge;
@protocol FiberFindBar;

namespace content {
class WebContents;
}

namespace fiber {

class FiberBrowserWindow;

// Chrome's FindBar for a Fiber window: its FindBarController drives the
// window's find bar (FiberFindBar in the bridge). The bar's actions do what
// FindBarView's do.
class FiberFindBar : public FindBar {
 public:
  FiberFindBar(FiberBrowserWindow* window, id<FiberFindBar> ui);
  FiberFindBar(const FiberFindBar&) = delete;
  FiberFindBar& operator=(const FiberFindBar&) = delete;
  ~FiberFindBar() override;

  // For FiberFindBarActionsBridge.
  void OnTextChanged(const std::u16string& text);
  void FindNext(bool forward);
  void Close();
  void OnFocusChanged(bool focused);

  // FindBar:
  FindBarController* GetFindBarController() const override;
  void SetFindBarController(FindBarController* find_bar_controller) override;
  void Show(bool animate, bool focus) override;
  void Hide(bool animate) override;
  void SetFocusAndSelection() override;
  void ClearResults(
      const find_in_page::FindNotificationDetails& results) override;
  void StopAnimation() override;
  void MoveWindowIfNecessary() override;
  void SetFindTextAndSelectedRange(const std::u16string& find_text,
                                   const gfx::Range& selected_range) override;
  std::u16string_view GetFindText() const override;
  gfx::Range GetSelectedRange() const override;
  void UpdateUIForFindResult(const find_in_page::FindNotificationDetails& result,
                             const std::u16string& find_text) override;
  void AudibleAlert() override;
  bool IsFindBarVisible() const override;
  void RestoreSavedFocus() override;
  bool HasGlobalFindPasteboard() const override;
  void UpdateFindBarForChangedWebContents() override;
  bool CanPopulateFromSelectedText() override;
  const FindBarTesting* GetFindBarTesting() const override;
  bool HasFocus() const override;
  void CloseOverlappingBubbles() override;
  views::Widget* GetHostWidget() override;

 private:
  // The tab the controller is on, or null.
  content::WebContents* GetWebContents() const;
  void SetVisible(bool visible);
  void SetFocusedOnCurrentTab(bool focused);

  const raw_ptr<FiberBrowserWindow> window_;
  id<FiberFindBar> __weak ui_;
  FiberFindBarActionsBridge* __strong actions_;
  raw_ptr<FindBarController> controller_ = nullptr;
  bool visible_ = false;
  // What GetFindText() views, from the field.
  mutable std::u16string find_text_;
};

}  // namespace fiber

#endif  // FIBER_BROWSER_FIND_BAR_FIBER_FIND_BAR_H_
