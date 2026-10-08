#ifndef FIBER_BROWSER_WINDOW_FIBER_BROWSER_WINDOW_H_
#define FIBER_BROWSER_WINDOW_FIBER_BROWSER_WINDOW_H_

#include <CoreGraphics/CoreGraphics.h>

#include <memory>
#include <optional>
#include <string>
#include <vector>

#include "base/memory/raw_ptr.h"
#include "base/memory/weak_ptr.h"
#include "chrome/browser/ui/browser_window.h"
#include "chrome/browser/ui/exclusive_access/exclusive_access_context.h"
#include "chrome/browser/ui/sad_tab.h"
#include "chrome/browser/ui/tabs/tab_strip_model_observer.h"
#include "content/public/browser/web_contents_observer.h"
#include "ui/base/accelerators/accelerator.h"
#include "ui/color/color_provider_source.h"
#include "ui/gfx/geometry/rect.h"
#include "ui/gfx/native_ui_types.h"

@class FiberBrowserWindowActions;
@class NSEvent;
@class NSView;
@class NSWindow;
@protocol FiberExtensionWindow;
@protocol FiberExtensionWindowActions;
@protocol FiberWindow;

namespace fiber {

class DownloadsWait;
class FiberDownloads;
class FiberExtensionsToolbar;
class HistorySwipeNavigation;
class FiberLocationBar;
class FiberStatusBubble;
class PinnedTabs;
class TabIndexSource;

// Chrome's BrowserWindow for Fiber's native windows (//fiber/ui, created
// through FiberWindowFactory), in place of Chrome's views-based BrowserView.
// Owned by the Browser, which deletes it via DeleteBrowserWindow() once closed.
class FiberBrowserWindow : public BrowserWindow,
                           public ExclusiveAccessContext,
                           public ui::AcceleratorProvider,
                           public ui::ColorProviderSource,
                           public TabStripModelObserver,
                           public content::WebContentsObserver {
 public:
  explicit FiberBrowserWindow(BrowserWindowInterface* browser);
  FiberBrowserWindow(const FiberBrowserWindow&) = delete;
  FiberBrowserWindow& operator=(const FiberBrowserWindow&) = delete;

  // The window a page is in: for a page in an extension's window, the browser
  // window its bubble is over.
  static FiberBrowserWindow* FromWebContents(
      content::WebContents* web_contents);
  static FiberBrowserWindow* FromNativeWindow(gfx::NativeWindow window);
  static FiberBrowserWindow* FromBrowser(BrowserWindowInterface* browser);

  BrowserWindowInterface* browser() const { return browser_; }
  base::WeakPtr<FiberBrowserWindow> GetWeakPtr() {
    return weak_factory_.GetWeakPtr();
  }

  // Shows a window an extension opened, as a bubble over this one's page.
  id<FiberExtensionWindow> AddExtensionWindow(
      id<FiberExtensionWindowActions> actions);
  // Whether `view` is in the active tab's page, not an extension window's.
  bool IsInActivePage(NSView* view) const;

  // Makes `web_contents` the active tab, if it's one of this window's.
  void ActivateTab(content::WebContents* web_contents);

  // Called by FiberBrowserWindowActions for what the user does in the window.
  void ExecuteCommand(int command, WindowOpenDisposition disposition);
  bool IsCommandEnabled(int command) const;
  bool IsActiveTabPinned() const;
  void FocusWebContents();
  // Focuses the active tab as Chrome would on switching to it.
  void RestoreFocus();
  // Selects the tab, in whichever of the profile's windows has it, and brings
  // that window forward.
  void SelectTab(int32_t tab_id);
  // Selects the tab, and finds `text` in its page.
  void RevealText(int32_t tab_id, const std::u16string& text);
  // Brings back a closed window or a previous session the command palette
  // lists (see TabIndexSource).
  void Restore(const std::string& restorable_id,
               std::optional<size_t> page_index);
  // Closes one of this window's tabs as the user would, so its page can ask
  // first and it can be reopened (see WillCloseTabs()).
  void CloseTab(int32_t tab_id);
  // The window's pins and their tabs; null if its profile has none.
  PinnedTabs* pinned_tabs() const { return pinned_tabs_.get(); }
  void OnCommandPaletteOpened();
  // Runs `event`'s main menu item ahead of the page with focus if it's a
  // shortcut pages don't get (see FiberWindowActions). Returns whether it ran.
  bool PerformReservedKeyEquivalent(NSEvent* event);
  // The active tab's key passthrough (see key_passthrough.h).
  bool CanStartKeyPassthrough() const;
  void SetKeyPassthrough(bool on);
  // A small image of the active tab's page, for the UI's dimming over it.
  void CapturePageThumbnail(void (^completion)(CGImageRef thumbnail));
  void OnWindowCloseRequested();
  void OnWindowActivationChanged(bool active);
  void OnWindowFullscreenChanged();
  // Saves where the window is to its session, as Chrome's windows do, and for
  // the next startup's window.
  void OnWindowFrameChanged();

  // Sends the UI what it shows of the active tab's page (the toolbar, the
  // window title, a sad tab).
  void UpdatePageState();
  // Sends the UI the active tab's docked DevTools, if any, and where they put
  // the page.
  void UpdateDevTools();
  // The button or help link of the active tab's sad tab was pressed.
  void PerformSadTabAction(SadTab::Action action);

  // Swiping between the active tab's pages, for FiberHistorySwiper. Each
  // mirrors a FiberWindow history swipe method (see FiberWindow.h).
  void BeginHistorySwipe(bool back);
  void UpdateHistorySwipe(double progress);
  void ReleaseHistorySwipe(void (^settled)(BOOL landed));
  void EndHistorySwipe(bool navigating);

  // BrowserWindow:
  gfx::NativeWindow GetNativeWindow() const override;
  bool IsOnCurrentWorkspace() const override;
  bool IsVisibleOnScreen() const override;
  void SetTopControlsShownRatio(content::WebContents* web_contents,
                                float ratio) override;
  bool DoBrowserControlsShrinkRendererSize(
      const content::WebContents* contents) const override;
  ui::NativeTheme* GetNativeTheme() override;
  const ui::ThemeProvider* GetThemeProvider() const override;
  int GetTopControlsHeight() const override;
  void SetTopControlsGestureScrollInProgress(bool in_progress) override;
  std::vector<StatusBubble*> GetStatusBubbles() override;
  void UpdateTitleBar() override;
  void UpdateLoadingAnimations(bool is_visible) override;
  void OnActiveTabChanged(content::WebContents* old_contents,
                          content::WebContents* new_contents,
                          int index,
                          int reason) override;
  void OnTabDetached(content::WebContents* contents, bool was_active) override;
  gfx::Size GetContentsSize() const override;
  void SetContentsSize(const gfx::Size& size) override;
  autofill::AutofillBubbleHandler* GetAutofillBubbleHandler() override;
  LocationBar* GetLocationBar() const override;
  ui::AcceleratorProvider* GetAcceleratorProvider() override;
  void SetFocusToLocationBar(bool is_user_initiated) override;
  void UpdateReloadStopState(bool is_loading, bool force) override;
  void UpdateToolbar(content::WebContents* contents) override;
  bool UpdateToolbarSecurityState() override;
  void UpdateCustomTabBarVisibility(bool visible, bool animate) override;
  void ResetToolbarTabState(content::WebContents* contents) override;
  void FocusToolbar() override;
  void ToolbarSizeChanged(bool is_animating) override;
  void TabDraggingStatusChanged(bool is_dragging) override;
  void LinkOpeningFromGesture(WindowOpenDisposition disposition) override;
  void FocusAppMenu() override;
  bool IsTabStripEditable() const override;
  void DisableTabStripEditingForTesting() override;
  bool IsToolbarVisible() const override;
  bool IsToolbarShowing() const override;
  bool IsLocationBarVisible() const override;
  void ShowUpdateChromeDialog() override;
  void ShowIntentPickerBubble(
      std::vector<apps::IntentPickerAppInfo> app_info,
      bool show_stay_in_chrome,
      bool show_remember_selection,
      apps::IntentPickerBubbleType bubble_type,
      const std::optional<url::Origin>& initiating_origin,
      IntentPickerResponse callback) override;
  void ShowBookmarkBubble(const GURL& url, bool already_bookmarked) override;
  ShowTranslateBubbleResult ShowTranslateBubble(
      content::WebContents* contents,
      translate::TranslateStep step,
      const std::string& source_language,
      const std::string& target_language,
      translate::TranslateErrors error_type,
      bool is_user_gesture) override;
  DownloadBubbleUIController* GetDownloadBubbleUIController() override;
  void ConfirmBrowserCloseWithPendingDownloads(
      int download_count,
      DownloadCloseType dialog_type,
      base::OnceCallback<void(bool)> callback) override;
  void ShowAppMenu() override;
  void PreHandleDragUpdate(const content::DropData& drop_data,
                           const gfx::PointF& point) override;
  void PreHandleDragExit() override;
  void HandleDragEnded() override;
  content::KeyboardEventProcessingResult PreHandleKeyboardEvent(
      const input::NativeWebKeyboardEvent& event) override;
  bool HandleKeyboardEvent(const input::NativeWebKeyboardEvent& event) override;
  std::unique_ptr<FindBar> CreateFindBar() override;
  web_modal::WebContentsModalDialogHost* GetWebContentsModalDialogHost()
      override;
  web_modal::WebContentsModalDialogHost* GetWebContentsModalDialogHostFor(
      content::WebContents* web_contents) override;
  void ShowAvatarBubbleFromAvatarButton(bool is_source_accelerator) override;
  void MaybeShowProfileSwitchIPH() override;
  void MaybeShowSupervisedUserProfileSignInIPH() override;
  void ShowHatsDialog(
      const std::string& site_id,
      const std::optional<std::string>& hats_histogram_name,
      const std::optional<uint64_t> hats_survey_ukm_id,
      base::OnceClosure success_callback,
      base::OnceClosure failure_callback,
      const SurveyBitsData& product_specific_bits_data,
      const SurveyStringData& product_specific_string_data) override;
  ExclusiveAccessContext* GetExclusiveAccessContext() override;
  std::string GetWorkspace() const override;
  bool IsVisibleOnAllWorkspaces() const override;
  void ShowEmojiPanel() override;
  std::unique_ptr<content::EyeDropper> OpenEyeDropper(
      content::RenderFrameHost* frame,
      content::EyeDropperListener* listener) override;
  void ShowCaretBrowsingDialog() override;
  void CreateTabSearchBubble() override;
  void CloseTabSearchBubble() override;
  void ShowIncognitoClearBrowsingDataDialog() override;
  void ShowIncognitoHistoryDisclaimerDialog() override;
  bool IsUnframedModeEnabled() const override;
  bool GetCanResize() override;
  ui::mojom::WindowShowState GetWindowShowState() const override;
  void ShowChromeLabs() override;
  BrowserView* AsBrowserView() override;

  // ui::BaseWindow:
  void Show() override;
  void ShowInactive() override;
  void Hide() override;
  bool IsVisible() const override;
  void SetBounds(const gfx::Rect& bounds) override;
  void Close() override;
  void Activate() override;
  void Deactivate() override;
  bool IsActive() const override;
  gfx::Rect GetBounds() const override;
  bool IsMaximized() const override;
  bool IsMinimized() const override;
  bool IsFullscreen() const override;  // Also ExclusiveAccessContext.
  gfx::Rect GetRestoredBounds() const override;
  ui::mojom::WindowShowState GetRestoredState() const override;
  void Maximize() override;
  void Minimize() override;
  void Restore() override;
  void FlashFrame(bool flash) override;
  ui::ZOrderLevel GetZOrderLevel() const override;
  void SetZOrderLevel(ui::ZOrderLevel order) override;

  // ExclusiveAccessContext:
  Profile* GetProfile() override;
  void EnterFullscreen(const url::Origin& origin,
                       ExclusiveAccessBubbleType bubble_type,
                       FullscreenTabParams fullscreen_tab_params) override;
  void ExitFullscreen() override;
  void UpdateExclusiveAccessBubble(
      const ExclusiveAccessBubbleParams& params,
      ExclusiveAccessBubbleHideCallback first_hide_callback) override;
  bool IsExclusiveAccessBubbleDisplayed() const override;
  void OnExclusiveAccessUserInput() override;
  content::WebContents* GetWebContentsForExclusiveAccess() override;
  bool CanUserEnterFullscreen() const override;
  bool CanUserExitFullscreen() const override;

  // ui::AcceleratorProvider:
  bool GetAcceleratorForCommandId(int command_id,
                                  ui::Accelerator* accelerator) const override;

  // ui::ColorProviderSource (GetColorProvider() is also a BrowserWindow
  // method):
  const ui::ColorProvider* GetColorProvider() const override;
  ui::ColorProviderKey GetColorProviderKey() const override;
  ui::RendererColorMap GetRendererColorMap(
      ui::ColorProviderKey::ColorMode color_mode,
      ui::ColorProviderKey::ForcedColors forced_colors) const override;

  // TabStripModelObserver:
  void OnTabStripModelChanged(TabStripModel* tab_strip_model,
                              const TabStripModelChange& change,
                              const TabStripSelectionChange& selection) override;
  void OnTabChangedAt(tabs::TabInterface* tab,
                      TabChangeType change_type) override;

  // content::WebContentsObserver (observes the active tab):
  void LoadProgressChanged(double progress) override;
  void DidStopLoading() override;
  void DidStartNavigation(
      content::NavigationHandle* navigation_handle) override;
  void BeforeUnloadFired(bool proceed) override;

 protected:
  // BrowserWindow:
  void DeleteBrowserWindow() override;

 private:
  ~FiberBrowserWindow() override;

  NSWindow* GetNSWindow() const;
  content::WebContents* GetActiveWebContents() const;
  // Whether `view` is in the active tab's page or its docked DevTools.
  bool IsInActiveTab(NSView* view) const;
  void UpdateLoadProgress();
  // Sends the UI the tab list, in tab strip order, and the pins.
  void UpdateTabs();
  void UpdatePins();
  // Before the user closes `count` of the window's tabs. Closing them all
  // leaves a browser window open on a New Tab page, and a lone New Tab page
  // stays. Returns whether to go ahead.
  bool WillCloseTabs(size_t count);

  const raw_ptr<BrowserWindowInterface> browser_;
  FiberBrowserWindowActions* __strong actions_;
  id<FiberWindow> __strong ui_;
  std::unique_ptr<FiberLocationBar> location_bar_;
  std::unique_ptr<FiberStatusBubble> status_bubble_;
  std::unique_ptr<FiberExtensionsToolbar> extensions_toolbar_;
  std::unique_ptr<FiberDownloads> downloads_;
  std::unique_ptr<PinnedTabs> pinned_tabs_;
  // The profile's, shared with its other windows.
  raw_ptr<TabIndexSource> tab_index_source_;
  // Its frame outside fullscreen, which is the one restored.
  gfx::Rect restored_bounds_;
  // Set while closing the window waits for its downloads.
  base::WeakPtr<DownloadsWait> downloads_wait_;
  // After a history swipe lands, until the page it went to shows.
  std::unique_ptr<HistorySwipeNavigation> history_swipe_navigation_;
  // The New Tab page opened for the last tab, while that tab's page may still
  // ask the user to stay.
  base::WeakPtr<content::WebContents> last_tab_replacement_;
  // Whether Chrome has shown the window. A startup window (see
  // ShowStartupWindow()) is on screen before then, but Chrome's startup
  // expects it hidden until it shows it.
  bool shown_ = false;
  base::WeakPtrFactory<FiberBrowserWindow> weak_factory_{this};
};

}  // namespace fiber

#endif  // FIBER_BROWSER_WINDOW_FIBER_BROWSER_WINDOW_H_
