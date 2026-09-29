#ifndef FIBER_BROWSER_EXTENSIONS_FIBER_EXTENSION_WINDOW_H_
#define FIBER_BROWSER_EXTENSIONS_FIBER_EXTENSION_WINDOW_H_

#include <memory>
#include <string>
#include <vector>

#include "base/callback_list.h"
#include "base/memory/raw_ptr.h"
#include "base/memory/weak_ptr.h"
#include "chrome/browser/ui/browser_window.h"
#include "chrome/browser/ui/exclusive_access/exclusive_access_context.h"
#include "content/public/browser/web_contents_observer.h"
#include "extensions/browser/extension_icon_image.h"
#include "ui/base/accelerators/accelerator.h"
#include "ui/base/window_open_disposition.h"

@class FiberExtensionWindowActionsBridge;
@protocol FiberExtensionWindow;

namespace fiber {

class ExtensionWindowLocationBar;
class FiberBrowserWindow;

// Chrome's BrowserWindow for a window an extension opened itself
// (chrome.windows.create): a bubble over a browser window's page, which it
// closes with. Extensions still see a window, minimized while collapsed.
class FiberExtensionWindow : public BrowserWindow,
                             public ExclusiveAccessContext,
                             public ui::AcceleratorProvider,
                             public extensions::IconImage::Observer,
                             public content::WebContentsObserver {
 public:
  // Whether `browser` is a window an extension opened: a popup whose app is
  // an extension.
  static bool IsExtensionWindow(BrowserWindowInterface* browser);
  // The browser window whose page such a window's bubble goes over: the last
  // active one of its profile, if any.
  static FiberBrowserWindow* HostFor(BrowserWindowInterface* browser);
  // `browser`'s window, if it's an extension's.
  static FiberExtensionWindow* FromBrowser(BrowserWindowInterface* browser);
  // Whether an extension's window over `host` is the active one.
  static bool IsActiveOver(const FiberBrowserWindow* host);

  FiberExtensionWindow(BrowserWindowInterface* browser,
                       FiberBrowserWindow* host);
  FiberExtensionWindow(const FiberExtensionWindow&) = delete;
  FiberExtensionWindow& operator=(const FiberExtensionWindow&) = delete;

  // Null once the browser window it's over is gone.
  FiberBrowserWindow* host() const { return host_.get(); }

  // Called by its actions.
  void OnCloseRequested();
  void OnExpanded();
  void OnActivationChanged(bool active);
  // Commands for its page run on its browser; the rest on the browser
  // window's.
  void ExecuteCommand(int command, WindowOpenDisposition disposition);
  bool IsCommandEnabled(int command) const;

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
  const ui::ColorProvider* GetColorProvider() const override;
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

  // extensions::IconImage::Observer:
  void OnExtensionIconImageChanged(extensions::IconImage* image) override;

  // content::WebContentsObserver (observes its page):
  void PrimaryPageChanged(content::Page& page) override;

 protected:
  // BrowserWindow:
  void DeleteBrowserWindow() override;

 private:
  ~FiberExtensionWindow() override;

  content::WebContents* GetActiveWebContents() const;
  void OnHostDidClose(BrowserWindowInterface* host);
  // Shows the page's site above it unless it's one of the extension's own.
  void UpdateSite();
  void FocusPage();

  const raw_ptr<BrowserWindowInterface> browser_;
  const std::string extension_id_;
  base::WeakPtr<FiberBrowserWindow> host_;
  FiberExtensionWindowActionsBridge* __strong actions_;
  id<FiberExtensionWindow> __strong ui_;
  std::unique_ptr<ExtensionWindowLocationBar> location_bar_;
  std::unique_ptr<extensions::IconImage> icon_;
  // The page's size, as the extension asked.
  gfx::Size contents_size_;
  // Shown, as a bubble with or without its panel.
  bool shown_ = false;
  // The browser counts it as active: its page has focus in the main window.
  bool active_ = false;
  base::CallbackListSubscription host_did_close_subscription_;
};

}  // namespace fiber

#endif  // FIBER_BROWSER_EXTENSIONS_FIBER_EXTENSION_WINDOW_H_
