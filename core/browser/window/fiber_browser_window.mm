#include "fiber/browser/window/fiber_browser_window.h"

#import <Cocoa/Cocoa.h>

#import "FiberBridge/FiberBridge.h"
#include "base/logging.h"
#include "base/no_destructor.h"
#include "base/notimplemented.h"
#include "base/strings/sys_string_conversions.h"
#include "chrome/app/chrome_command_ids.h"
#include "chrome/browser/global_keyboard_shortcuts_mac.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/themes/theme_service.h"
#include "chrome/browser/ui/browser_active_state_manager/browser_active_state_manager.h"
#include "chrome/browser/ui/browser_commands.h"
#include "chrome/browser/ui/browser_window/public/browser_window_features.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#include "chrome/browser/ui/browser_window_state.h"
#include "chrome/browser/ui/exclusive_access/exclusive_access_manager.h"
#include "chrome/browser/ui/exclusive_access/fullscreen_controller.h"
#include "chrome/browser/ui/find_bar/find_bar.h"
#include "chrome/browser/ui/status_bubble.h"
#include "chrome/browser/ui/tabs/tab_strip_model.h"
#include "chrome/browser/ui/tabs/tab_strip_user_gesture_details.h"
#include "chrome/browser/ui/unload_controller.h"
#include "chrome/common/webui_url_constants.h"
#include "components/input/native_web_keyboard_event.h"
#include "components/omnibox/browser/location_bar_model.h"
#include "components/tabs/public/tab_interface.h"
#include "components/url_formatter/elide_url.h"
#include "components/url_formatter/url_formatter.h"
#include "content/public/browser/eye_dropper.h"
#include "content/public/browser/keyboard_event_processing_result.h"
#include "content/public/browser/navigation_controller.h"
#include "content/public/browser/navigation_entry.h"
#include "content/public/browser/navigation_handle.h"
#include "content/public/browser/web_contents.h"
#include "content/public/common/url_constants.h"
#include "fiber/browser/downloads/downloads_wait.h"
#include "fiber/browser/extensions/fiber_extension_window.h"
#include "fiber/browser/extensions/fiber_extensions_toolbar.h"
#include "fiber/browser/palette/tab_index_source.h"
#include "fiber/browser/swipe/history_swipe_navigation.h"
#include "fiber/browser/swipe/page_snapshots.h"
#import "fiber/browser/window/fiber_browser_window_actions.h"
#include "fiber/browser/window/fiber_location_bar.h"
#include "fiber/browser/window/fiber_main_menu.h"
#include "fiber/browser/window/tab_state.h"
#include "ui/base/mojom/window_show_state.mojom.h"
#include "ui/color/color_provider_manager.h"
#include "ui/color/color_provider_utils.h"
#include "ui/gfx/mac/coordinate_conversion.h"
#include "ui/native_theme/native_theme.h"

namespace fiber {

namespace {

std::vector<FiberBrowserWindow*>& AllWindows() {
  static base::NoDestructor<std::vector<FiberBrowserWindow*>> windows;
  return *windows;
}

// Commands whose UI Fiber doesn't have yet. Chrome's implementations assume
// its views UI and would crash or show nothing.
bool IsCommandSupported(int command) {
  switch (command) {
    case IDC_FIND:
    case IDC_FIND_NEXT:
    case IDC_FIND_PREVIOUS:
    case IDC_FIND_AND_EDIT_MENU:
    case IDC_SHOW_APP_MENU:
    case IDC_SHOW_AVATAR_MENU:
    case IDC_FOCUS_TOOLBAR:
    case IDC_FOCUS_BOOKMARKS:
    case IDC_FOCUS_NEXT_PANE:
    case IDC_FOCUS_PREVIOUS_PANE:
      return false;
    default:
      return true;
  }
}

// Fiber's New Tab page (chrome://newtab): the page the tab shows, or before
// that, the one it's loading. The URL is the one loaded, so an extension's
// New Tab page, which only shows as chrome://newtab, doesn't count.
bool IsNewTabPage(content::WebContents* contents) {
  content::NavigationController& navigation = contents->GetController();
  content::NavigationEntry* entry = navigation.GetLastCommittedEntry();
  if (!entry || entry->IsInitialEntry()) {
    entry = navigation.GetVisibleEntry();
  }
  return entry && entry->GetURL().SchemeIs(content::kChromeUIScheme) &&
         entry->GetURL().host() == chrome::kChromeUINewTabHost;
}

}  // namespace

// Shows the hovered link, or failing that the page's load status, in the
// window's status bubble.
class FiberStatusBubble : public StatusBubble {
 public:
  explicit FiberStatusBubble(id<FiberWindow> ui) : ui_(ui) {}

  // StatusBubble:
  void SetStatus(const std::u16string& status) override {
    status_ = status;
    Refresh();
  }
  void SetURL(const GURL& url) override {
    url_ = url.is_empty() ? std::u16string() : url_formatter::FormatUrl(url);
    Refresh();
  }
  void Hide() override {
    status_.clear();
    url_.clear();
    Refresh();
  }
  void MouseMoved(bool left_content) override {}

 private:
  void Refresh() {
    [ui_ setStatusText:base::SysUTF16ToNSString(url_.empty() ? status_ : url_)];
  }

  id<FiberWindow> __weak ui_;
  std::u16string status_;
  std::u16string url_;
};

// static
FiberBrowserWindow* FiberBrowserWindow::FromWebContents(
    content::WebContents* web_contents) {
  tabs::TabInterface* tab =
      tabs::TabInterface::MaybeGetFromContents(web_contents);
  BrowserWindowInterface* browser =
      tab ? tab->GetBrowserWindowInterface() : nullptr;
  if (!browser) {
    return nullptr;
  }
  if (FiberExtensionWindow* extension_window =
          FiberExtensionWindow::FromBrowser(browser)) {
    return extension_window->host();
  }
  BrowserWindow* window = BrowserWindow::FromBrowser(browser);
  for (FiberBrowserWindow* fiber_window : AllWindows()) {
    if (fiber_window == window) {
      return fiber_window;
    }
  }
  return nullptr;
}

// static
FiberBrowserWindow* FiberBrowserWindow::FromNativeWindow(
    gfx::NativeWindow window) {
  for (FiberBrowserWindow* fiber_window : AllWindows()) {
    if (fiber_window->GetNativeWindow() == window) {
      return fiber_window;
    }
  }
  return nullptr;
}

// static
FiberBrowserWindow* FiberBrowserWindow::FromBrowser(
    BrowserWindowInterface* browser) {
  if (!browser) {
    return nullptr;
  }
  for (FiberBrowserWindow* fiber_window : AllWindows()) {
    if (fiber_window->browser_ == browser) {
      return fiber_window;
    }
  }
  return nullptr;
}

FiberBrowserWindow::FiberBrowserWindow(BrowserWindowInterface* browser)
    : browser_(browser) {
  AllWindows().push_back(this);
  InstallMainMenuItems();
  // Chrome's window sizer: saved placement, cascading, or a popup's requested
  // bounds.
  gfx::Rect bounds;
  ui::mojom::WindowShowState show_state;
  chrome::GetSavedWindowBoundsAndShowState(browser_, &bounds, &show_state);
  actions_ = [[FiberBrowserWindowActions alloc] initWithOwner:this];
  tab_index_source_ = TabIndexSource::AddWindow(this);
  ui_ = [FiberWindowFactory
      windowWithFrame:bounds.IsEmpty() ? NSZeroRect
                                       : gfx::ScreenRectToNSRect(bounds)
              actions:actions_
             tabIndex:tab_index_source_->index()];
  location_bar_ = std::make_unique<FiberLocationBar>(this, ui_.omnibox);
  status_bubble_ = std::make_unique<FiberStatusBubble>(ui_);
  extensions_toolbar_ =
      std::make_unique<FiberExtensionsToolbar>(browser_, ui_.extensions);
  browser_->GetTabStripModel()->AddObserver(this);
}

FiberBrowserWindow::~FiberBrowserWindow() {
  // Its popup and actions go while the browser's features are still there.
  extensions_toolbar_.reset();
  if (downloads_wait_) {
    downloads_wait_->Close();
  }
  std::erase(AllWindows(), this);
  browser_->GetFeatures().TearDownPreBrowserWindowDestruction();
  Observe(nullptr);
  tab_index_source_ = nullptr;
  TabIndexSource::RemoveWindow(this);
  [actions_ detachOwner];
  [GetNSWindow() close];
}

void FiberBrowserWindow::DeleteBrowserWindow() {
  delete this;
}

void FiberBrowserWindow::BeginHistorySwipe(bool back) {
  // A swipe that lands while the last one's page is still coming.
  history_swipe_navigation_.reset();
  content::WebContents* web_contents = GetActiveWebContents();
  [ui_ beginHistorySwipeInDirection:back ? FiberHistorySwipeDirectionBack
                                         : FiberHistorySwipeDirectionForward
                           snapshot:web_contents ? PageSnapshotAtOffset(
                                                       web_contents,
                                                       back ? -1 : 1)
                                                 : nil];
}

void FiberBrowserWindow::UpdateHistorySwipe(double progress) {
  [ui_ updateHistorySwipe:progress];
}

void FiberBrowserWindow::ReleaseHistorySwipe(void (^settled)(BOOL landed)) {
  [ui_ releaseHistorySwipe:settled];
}

void FiberBrowserWindow::EndHistorySwipe(bool navigating) {
  [ui_ endHistorySwipeNavigating:navigating];
  content::WebContents* web_contents = GetActiveWebContents();
  if (!navigating || !web_contents) {
    [ui_ finishHistorySwipeNavigation];
    return;
  }
  history_swipe_navigation_ = std::make_unique<HistorySwipeNavigation>(
      web_contents, base::BindOnce(
                        [](FiberBrowserWindow* window) {
                          [window->ui_ finishHistorySwipeNavigation];
                          window->history_swipe_navigation_.reset();
                        },
                        base::Unretained(this)));
}

void FiberBrowserWindow::ExecuteCommand(int command,
                                        WindowOpenDisposition disposition) {
  if (IsCommandEnabled(command)) {
    chrome::ExecuteCommandWithDisposition(browser_, command, disposition);
  }
}

bool FiberBrowserWindow::IsCommandEnabled(int command) const {
  return IsCommandSupported(command) &&
         chrome::IsCommandEnabled(browser_, command);
}

void FiberBrowserWindow::FocusWebContents() {
  if (content::WebContents* contents = GetActiveWebContents()) {
    contents->Focus();
  }
}

void FiberBrowserWindow::SelectTab(int32_t tab_id) {
  tabs::TabInterface* tab = tabs::TabHandle(tab_id).Get();
  FiberBrowserWindow* window =
      tab ? FromBrowser(tab->GetBrowserWindowInterface()) : nullptr;
  if (!window || window->GetProfile() != GetProfile()) {
    return;
  }
  TabStripModel* model = window->browser_->GetTabStripModel();
  int index = model->GetIndexOfTab(tab);
  if (index == TabStripModel::kNoTab) {
    return;
  }
  model->ActivateTabAt(index,
                       TabStripUserGestureDetails(
                           TabStripUserGestureDetails::GestureType::kMouse));
  if (window != this) {
    window->Activate();
  }
}

void FiberBrowserWindow::RevealText(int32_t tab_id,
                                    const std::u16string& text) {
  SelectTab(tab_id);
  if (tabs::TabInterface* tab = tabs::TabHandle(tab_id).Get()) {
    tab_index_source_->RevealText(tab->GetContents(), text);
  }
}

void FiberBrowserWindow::OnCommandPaletteOpened() {
  if (content::WebContents* contents = GetActiveWebContents()) {
    tab_index_source_->ReadPageText(contents);
  }
}

id<FiberExtensionWindow> FiberBrowserWindow::AddExtensionWindow(
    id<FiberExtensionWindowActions> actions) {
  return [ui_.extensions extensionWindowWithActions:actions];
}

bool FiberBrowserWindow::IsInActivePage(NSView* view) const {
  content::WebContents* contents = GetActiveWebContents();
  return contents &&
         [view isDescendantOf:contents->GetNativeView().GetNativeNSView()];
}

void FiberBrowserWindow::ActivateTab(content::WebContents* web_contents) {
  TabStripModel* model = browser_->GetTabStripModel();
  const int index =
      web_contents ? model->GetIndexOfWebContents(web_contents)
                   : TabStripModel::kNoTab;
  if (index != TabStripModel::kNoTab && index != model->active_index()) {
    model->ActivateTabAt(index);
  }
}

void FiberBrowserWindow::OnWindowCloseRequested() {
  Close();
}

void FiberBrowserWindow::OnWindowActivationChanged(bool active) {
  // Chrome lets go of a closing browser, which can't become active again.
  if (active && browser_->IsDeleteScheduled()) {
    return;
  }
  if (active) {
    BrowserActiveStateManager::From(browser_)->DidBecomeActive();
  } else {
    BrowserActiveStateManager::From(browser_)->DidBecomeInactive();
  }
}

void FiberBrowserWindow::OnWindowFullscreenChanged() {
  ExclusiveAccessManager* manager = ExclusiveAccessManager::From(browser_);
  if (!manager) {
    return;
  }
  FullscreenController* controller = manager->fullscreen_controller();
  // Page-requested fullscreen (e.g. video) shows only the page.
  [ui_ setControlsVisible:!(IsFullscreen() && controller->IsTabFullscreen())];
  controller->WindowFullscreenStateChanged();
}

NSWindow* FiberBrowserWindow::GetNSWindow() const {
  return ui_.window;
}

content::WebContents* FiberBrowserWindow::GetActiveWebContents() const {
  return browser_->GetTabStripModel()->GetActiveWebContents();
}

void FiberBrowserWindow::UpdateLoadProgress() {
  content::WebContents* contents = GetActiveWebContents();
  [ui_ setLoading:contents && contents->ShouldShowLoadingUI()
         progress:contents ? contents->GetLoadProgress() : 1];
}

void FiberBrowserWindow::UpdateTabs() {
  TabStripModel* model = browser_->GetTabStripModel();
  NSMutableArray<FiberTabState*>* tabs =
      [NSMutableArray arrayWithCapacity:model->count()];
  for (int i = 0; i < model->count(); ++i) {
    [tabs addObject:TabStateFor(model->GetTabAtIndex(i))];
  }
  tabs::TabInterface* active = model->GetActiveTab();
  [ui_ setTabs:tabs
      activeTabID:active ? active->GetHandle().raw_value()
                         : tabs::TabHandle::NullValue];
  if (tab_index_source_) {
    tab_index_source_->TabsChanged();
  }
}

// BrowserWindow:

gfx::NativeWindow FiberBrowserWindow::GetNativeWindow() const {
  return gfx::NativeWindow(GetNSWindow());
}

bool FiberBrowserWindow::IsOnCurrentWorkspace() const {
  return GetNSWindow().onActiveSpace;
}

bool FiberBrowserWindow::IsVisibleOnScreen() const {
  return GetNSWindow().visible &&
         (GetNSWindow().occlusionState & NSWindowOcclusionStateVisible);
}

void FiberBrowserWindow::SetTopControlsShownRatio(
    content::WebContents* web_contents,
    float ratio) {}

bool FiberBrowserWindow::DoBrowserControlsShrinkRendererSize(
    const content::WebContents* contents) const {
  return false;
}

ui::NativeTheme* FiberBrowserWindow::GetNativeTheme() {
  return ui::NativeTheme::GetInstanceForNativeUi();
}

const ui::ThemeProvider* FiberBrowserWindow::GetThemeProvider() const {
  return &ThemeService::GetThemeProviderForProfile(browser_->GetProfile());
}

int FiberBrowserWindow::GetTopControlsHeight() const {
  return 0;
}

void FiberBrowserWindow::SetTopControlsGestureScrollInProgress(
    bool in_progress) {}

std::vector<StatusBubble*> FiberBrowserWindow::GetStatusBubbles() {
  return {status_bubble_.get()};
}

void FiberBrowserWindow::UpdateTitleBar() {
  UpdatePageState();
}

void FiberBrowserWindow::UpdateLoadingAnimations(bool is_visible) {}

void FiberBrowserWindow::OnActiveTabChanged(content::WebContents* old_contents,
                                            content::WebContents* new_contents,
                                            int index,
                                            int reason) {
  // The last tab's swipe is over (the UI takes it down with the view).
  history_swipe_navigation_.reset();
  // Swapping the view in and out of the window also updates each tab's
  // visibility, via WebContentsViewCocoa.
  [ui_ setContentsView:new_contents->GetNativeView().GetNativeNSView()];
  new_contents->SetColorProviderSource(this);
  Observe(new_contents);
  UpdateToolbar(new_contents);
  UpdateLoadProgress();
  // Like BrowserView, and only once the window is showing (see Show()).
  if (GetNSWindow().visible) {
    RestoreFocus();
  }
}

void FiberBrowserWindow::RestoreFocus() {
  // With no focus stored for it (Chrome stores it in views), the tab focuses
  // its page, or, on the New Tab page, the location bar: Fiber's command
  // palette.
  if (content::WebContents* contents = GetActiveWebContents()) {
    contents->RestoreFocus();
  }
}

void FiberBrowserWindow::OnTabDetached(content::WebContents* contents,
                                       bool was_active) {
  if (was_active) {
    [ui_ setContentsView:nil];
    Observe(nullptr);
  }
}

gfx::Size FiberBrowserWindow::GetContentsSize() const {
  return gfx::Size(NSSizeToCGSize(GetNSWindow().contentView.bounds.size));
}

void FiberBrowserWindow::SetContentsSize(const gfx::Size& size) {
  [GetNSWindow() setContentSize:NSMakeSize(size.width(), size.height())];
}

autofill::AutofillBubbleHandler*
FiberBrowserWindow::GetAutofillBubbleHandler() {
  NOTIMPLEMENTED_LOG_ONCE();
  return nullptr;
}

LocationBar* FiberBrowserWindow::GetLocationBar() const {
  return location_bar_.get();
}

ui::AcceleratorProvider* FiberBrowserWindow::GetAcceleratorProvider() {
  return this;
}

void FiberBrowserWindow::SetFocusToLocationBar(bool is_user_initiated) {
  location_bar_->FocusLocation(is_user_initiated,
                               /*clear_focus_if_failed=*/false);
}

void FiberBrowserWindow::UpdateReloadStopState(bool is_loading, bool force) {
  UpdatePageState();
}

void FiberBrowserWindow::UpdateToolbar(content::WebContents* contents) {
  // Like BrowserView's toolbar, via the location bar, which also updates the
  // page state.
  location_bar_->Update(contents);
}

void FiberBrowserWindow::UpdatePageState() {
  content::WebContents* active = GetActiveWebContents();
  if (!active) {
    return;
  }
  // Chrome's model decides what to show, e.g. nothing on the New Tab page.
  LocationBarModel* model = browser_->GetFeatures().location_bar_model();
  NSString* display_url = @"";
  if (model->ShouldDisplayURL()) {
    display_url = base::SysUTF16ToNSString(
        url_formatter::FormatUrlForDisplayOmitSchemePathAndTrivialSubdomains(
            model->GetURL()));
  }
  content::NavigationController& navigation = active->GetController();
  [ui_ setPageState:[[FiberPageState alloc]
                        initWithDisplayURL:display_url
                                     title:base::SysUTF16ToNSString(
                                               active->GetTitle())
                                 canGoBack:navigation.CanGoBack()
                              canGoForward:navigation.CanGoForward()
                                   loading:active->IsLoading()
                                newTabPage:IsNewTabPage(active)]];
}

bool FiberBrowserWindow::UpdateToolbarSecurityState() {
  return false;
}

void FiberBrowserWindow::UpdateCustomTabBarVisibility(bool visible,
                                                      bool animate) {}

void FiberBrowserWindow::ResetToolbarTabState(content::WebContents* contents) {
  location_bar_->ResetTabState(contents);
  UpdatePageState();
}

void FiberBrowserWindow::FocusToolbar() {}

void FiberBrowserWindow::ToolbarSizeChanged(bool is_animating) {}

void FiberBrowserWindow::TabDraggingStatusChanged(bool is_dragging) {}

void FiberBrowserWindow::LinkOpeningFromGesture(
    WindowOpenDisposition disposition) {}

void FiberBrowserWindow::FocusAppMenu() {}

bool FiberBrowserWindow::IsTabStripEditable() const {
  return true;
}

void FiberBrowserWindow::DisableTabStripEditingForTesting() {}

bool FiberBrowserWindow::IsToolbarVisible() const {
  return true;
}

bool FiberBrowserWindow::IsToolbarShowing() const {
  return true;
}

bool FiberBrowserWindow::IsLocationBarVisible() const {
  return true;
}

void FiberBrowserWindow::ShowUpdateChromeDialog() {}

void FiberBrowserWindow::ShowIntentPickerBubble(
    std::vector<apps::IntentPickerAppInfo> app_info,
    bool show_stay_in_chrome,
    bool show_remember_selection,
    apps::IntentPickerBubbleType bubble_type,
    const std::optional<url::Origin>& initiating_origin,
    IntentPickerResponse callback) {
  NOTIMPLEMENTED_LOG_ONCE();
}

void FiberBrowserWindow::ShowBookmarkBubble(const GURL& url,
                                            bool already_bookmarked) {
  NOTIMPLEMENTED_LOG_ONCE();
}

ShowTranslateBubbleResult FiberBrowserWindow::ShowTranslateBubble(
    content::WebContents* contents,
    translate::TranslateStep step,
    const std::string& source_language,
    const std::string& target_language,
    translate::TranslateErrors error_type,
    bool is_user_gesture) {
  return ShowTranslateBubbleResult::kBrowserWindowNotValid;
}

DownloadBubbleUIController*
FiberBrowserWindow::GetDownloadBubbleUIController() {
  NOTIMPLEMENTED_LOG_ONCE();
  return nullptr;
}

void FiberBrowserWindow::ConfirmBrowserCloseWithPendingDownloads(
    int download_count,
    DownloadCloseType dialog_type,
    base::OnceCallback<void(bool)> callback) {
  // On the Mac, only an Incognito or Guest profile's last window gets here:
  // closing it would cancel the profile's downloads. The close waits for them.
  if (downloads_wait_) {
    std::move(callback).Run(false);
    return;
  }
  downloads_wait_ = DownloadsWait::Start(
      DownloadsWait::Reason::kCloseWindow, {browser_->GetProfile()},
      GetNativeWindow(), std::move(callback));
}

void FiberBrowserWindow::ShowAppMenu() {}

void FiberBrowserWindow::PreHandleDragUpdate(const content::DropData& drop_data,
                                             const gfx::PointF& point) {}

void FiberBrowserWindow::PreHandleDragExit() {}

void FiberBrowserWindow::HandleDragEnded() {}

content::KeyboardEventProcessingResult
FiberBrowserWindow::PreHandleKeyboardEvent(
    const input::NativeWebKeyboardEvent& event) {
  // The page sees keys first; HandleKeyboardEvent() gets what it doesn't use.
  return content::KeyboardEventProcessingResult::NOT_HANDLED;
}

bool FiberBrowserWindow::HandleKeyboardEvent(
    const input::NativeWebKeyboardEvent& event) {
  // Give keys the page didn't handle to the main menu, so shortcuts like
  // Cmd-L work while the page has focus.
  if (event.skip_if_unhandled ||
      event.GetType() == input::NativeWebKeyboardEvent::Type::kChar) {
    return false;
  }
  NSEvent* ns_event = event.os_event.Get();
  return ns_event.type == NSEventTypeKeyDown &&
         [NSApp.mainMenu performKeyEquivalent:ns_event];
}

std::unique_ptr<FindBar> FiberBrowserWindow::CreateFindBar() {
  // Unreachable while IDC_FIND is unsupported.
  NOTREACHED();
}

web_modal::WebContentsModalDialogHost*
FiberBrowserWindow::GetWebContentsModalDialogHost() {
  NOTIMPLEMENTED_LOG_ONCE();
  return nullptr;
}

web_modal::WebContentsModalDialogHost*
FiberBrowserWindow::GetWebContentsModalDialogHostFor(
    content::WebContents* web_contents) {
  return GetWebContentsModalDialogHost();
}

void FiberBrowserWindow::ShowAvatarBubbleFromAvatarButton(
    bool is_source_accelerator) {}

void FiberBrowserWindow::MaybeShowProfileSwitchIPH() {}

void FiberBrowserWindow::MaybeShowSupervisedUserProfileSignInIPH() {}

void FiberBrowserWindow::ShowHatsDialog(
    const std::string& site_id,
    const std::optional<std::string>& hats_histogram_name,
    const std::optional<uint64_t> hats_survey_ukm_id,
    base::OnceClosure success_callback,
    base::OnceClosure failure_callback,
    const SurveyBitsData& product_specific_bits_data,
    const SurveyStringData& product_specific_string_data) {
  std::move(failure_callback).Run();
}

ExclusiveAccessContext* FiberBrowserWindow::GetExclusiveAccessContext() {
  return this;
}

std::string FiberBrowserWindow::GetWorkspace() const {
  return std::string();
}

bool FiberBrowserWindow::IsVisibleOnAllWorkspaces() const {
  return GetNSWindow().collectionBehavior &
         NSWindowCollectionBehaviorCanJoinAllSpaces;
}

void FiberBrowserWindow::ShowEmojiPanel() {
  [NSApp orderFrontCharacterPalette:nil];
}

std::unique_ptr<content::EyeDropper> FiberBrowserWindow::OpenEyeDropper(
    content::RenderFrameHost* frame,
    content::EyeDropperListener* listener) {
  NOTIMPLEMENTED_LOG_ONCE();
  return nullptr;
}

void FiberBrowserWindow::ShowCaretBrowsingDialog() {}

void FiberBrowserWindow::CreateTabSearchBubble() {
  // Search Tabs: the command palette, in place of Chrome's Tab Search.
  [ui_ showCommandPalette];
}

void FiberBrowserWindow::CloseTabSearchBubble() {}

void FiberBrowserWindow::ShowIncognitoClearBrowsingDataDialog() {}

void FiberBrowserWindow::ShowIncognitoHistoryDisclaimerDialog() {}

bool FiberBrowserWindow::IsUnframedModeEnabled() const {
  return false;
}

bool FiberBrowserWindow::GetCanResize() {
  return true;
}

ui::mojom::WindowShowState FiberBrowserWindow::GetWindowShowState() const {
  if (IsFullscreen()) {
    return ui::mojom::WindowShowState::kFullscreen;
  }
  if (IsMinimized()) {
    return ui::mojom::WindowShowState::kMinimized;
  }
  if (IsMaximized()) {
    return ui::mojom::WindowShowState::kMaximized;
  }
  return ui::mojom::WindowShowState::kDefault;
}

void FiberBrowserWindow::ShowChromeLabs() {}

BrowserView* FiberBrowserWindow::AsBrowserView() {
  return nullptr;
}

// ui::BaseWindow:

void FiberBrowserWindow::Show() {
  // Like BrowserView::Show(): the browser has to count as the last active one
  // as soon as this returns, before AppKit reports the window becoming main.
  BrowserActiveStateManager::From(browser_)->DidBecomeActive();
  [GetNSWindow() makeKeyAndOrderFront:nil];
  RestoreFocus();
}

void FiberBrowserWindow::ShowInactive() {
  [GetNSWindow() orderFront:nil];
}

void FiberBrowserWindow::Hide() {
  [GetNSWindow() orderOut:nil];
}

bool FiberBrowserWindow::IsVisible() const {
  return GetNSWindow().visible;
}

void FiberBrowserWindow::SetBounds(const gfx::Rect& bounds) {
  [GetNSWindow() setFrame:gfx::ScreenRectToNSRect(bounds) display:YES];
}

void FiberBrowserWindow::Close() {
  // Mirrors WebUIBrowserWindow::OnWindowCloseRequested(). Unload handlers
  // may stop the close; otherwise the tabs close, the Browser calls Close()
  // again once they're gone, and then deletes this asynchronously.
  UnloadController* unload_controller = UnloadController::From(browser_);
  if (!unload_controller->HandleBeforeClose()) {
    return;
  }
  unload_controller->OnWindowClosing();
  // Look closed while the tabs shut down.
  [GetNSWindow() orderOut:nil];
}

void FiberBrowserWindow::Activate() {
  [GetNSWindow() makeKeyAndOrderFront:nil];
  // Always available: Fiber requires macOS 26, but Chromium's C++ compiles for
  // older releases.
  if (@available(macOS 14, *)) {
    [NSApp activate];
  }
}

void FiberBrowserWindow::Deactivate() {}

bool FiberBrowserWindow::IsActive() const {
  // An extension's window over it may have focus instead.
  return GetNSWindow().mainWindow && !FiberExtensionWindow::IsActiveOver(this);
}

gfx::Rect FiberBrowserWindow::GetBounds() const {
  return gfx::ScreenRectFromNSRect(GetNSWindow().frame);
}

bool FiberBrowserWindow::IsMaximized() const {
  return GetNSWindow().zoomed;
}

bool FiberBrowserWindow::IsMinimized() const {
  return GetNSWindow().miniaturized;
}

bool FiberBrowserWindow::IsFullscreen() const {
  return GetNSWindow().styleMask & NSWindowStyleMaskFullScreen;
}

gfx::Rect FiberBrowserWindow::GetRestoredBounds() const {
  return GetBounds();
}

ui::mojom::WindowShowState FiberBrowserWindow::GetRestoredState() const {
  return ui::mojom::WindowShowState::kDefault;
}

void FiberBrowserWindow::Maximize() {
  if (!IsMaximized()) {
    [GetNSWindow() zoom:nil];
  }
}

void FiberBrowserWindow::Minimize() {
  [GetNSWindow() miniaturize:nil];
}

void FiberBrowserWindow::Restore() {
  if (IsMinimized()) {
    [GetNSWindow() deminiaturize:nil];
  } else if (IsFullscreen()) {
    [GetNSWindow() toggleFullScreen:nil];
  } else if (IsMaximized()) {
    [GetNSWindow() zoom:nil];
  }
}

void FiberBrowserWindow::FlashFrame(bool flash) {
  if (flash) {
    [NSApp requestUserAttention:NSInformationalRequest];
  }
}

ui::ZOrderLevel FiberBrowserWindow::GetZOrderLevel() const {
  return GetNSWindow().level == NSFloatingWindowLevel
             ? ui::ZOrderLevel::kFloatingWindow
             : ui::ZOrderLevel::kNormal;
}

void FiberBrowserWindow::SetZOrderLevel(ui::ZOrderLevel order) {
  GetNSWindow().level = order == ui::ZOrderLevel::kNormal
                            ? NSNormalWindowLevel
                            : NSFloatingWindowLevel;
}

// ExclusiveAccessContext:

Profile* FiberBrowserWindow::GetProfile() {
  return browser_->GetProfile();
}

void FiberBrowserWindow::EnterFullscreen(
    const url::Origin& origin,
    ExclusiveAccessBubbleType bubble_type,
    FullscreenTabParams fullscreen_tab_params) {
  if (IsFullscreen()) {
    // Already fullscreen; the page may have just taken it over.
    OnWindowFullscreenChanged();
  } else {
    [GetNSWindow() toggleFullScreen:nil];
  }
}

void FiberBrowserWindow::ExitFullscreen() {
  if (IsFullscreen()) {
    [GetNSWindow() toggleFullScreen:nil];
  }
}

void FiberBrowserWindow::UpdateExclusiveAccessBubble(
    const ExclusiveAccessBubbleParams& params,
    ExclusiveAccessBubbleHideCallback first_hide_callback) {
  // TODO: Show the "Press Esc to exit full screen" bubble.
}

bool FiberBrowserWindow::IsExclusiveAccessBubbleDisplayed() const {
  return false;
}

void FiberBrowserWindow::OnExclusiveAccessUserInput() {}

content::WebContents* FiberBrowserWindow::GetWebContentsForExclusiveAccess() {
  return GetActiveWebContents();
}

bool FiberBrowserWindow::CanUserEnterFullscreen() const {
  return true;
}

bool FiberBrowserWindow::CanUserExitFullscreen() const {
  return true;
}

// ui::AcceleratorProvider:

bool FiberBrowserWindow::GetAcceleratorForCommandId(
    int command_id,
    ui::Accelerator* accelerator) const {
  return GetDefaultMacAcceleratorForCommandId(command_id, accelerator);
}

// ui::ColorProviderSource:

const ui::ColorProvider* FiberBrowserWindow::GetColorProvider() const {
  return ui::ColorProviderManager::Get().GetColorProviderFor(
      GetColorProviderKey());
}

ui::ColorProviderKey FiberBrowserWindow::GetColorProviderKey() const {
  // TODO: Follow the profile's theme settings like BrowserView does.
  return ui::NativeTheme::GetInstanceForNativeUi()->GetColorProviderKey(
      /*custom_theme=*/nullptr);
}

ui::RendererColorMap FiberBrowserWindow::GetRendererColorMap(
    ui::ColorProviderKey::ColorMode color_mode,
    ui::ColorProviderKey::ForcedColors forced_colors) const {
  ui::ColorProviderKey key = GetColorProviderKey();
  key.color_mode = color_mode;
  key.forced_colors = forced_colors;
  return ui::CreateRendererColorMap(
      *ui::ColorProviderManager::Get().GetColorProviderFor(key));
}

// TabStripModelObserver:

void FiberBrowserWindow::OnTabStripModelChanged(
    TabStripModel* tab_strip_model,
    const TabStripModelChange& change,
    const TabStripSelectionChange& selection) {
  UpdateTabs();
}

void FiberBrowserWindow::OnTabChangedAt(tabs::TabInterface* tab,
                                        TabChangeType change_type) {
  UpdateTabs();
}

// content::WebContentsObserver:

void FiberBrowserWindow::LoadProgressChanged(double progress) {
  UpdateLoadProgress();
}

void FiberBrowserWindow::DidStopLoading() {
  UpdateLoadProgress();
}

void FiberBrowserWindow::DidStartNavigation(
    content::NavigationHandle* navigation_handle) {
  // The page being left, for a swipe back (or forward) to it.
  if (navigation_handle->IsInPrimaryMainFrame()) {
    CapturePageSnapshot(web_contents());
  }
}

}  // namespace fiber
