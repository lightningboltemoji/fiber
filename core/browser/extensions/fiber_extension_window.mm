#include "fiber/browser/extensions/fiber_extension_window.h"

#import <AppKit/AppKit.h>

#include <algorithm>
#include <utility>

#import "FiberBridge/FiberExtensions.h"
#include "base/functional/bind.h"
#include "base/memory/raw_ptr.h"
#include "base/no_destructor.h"
#include "base/notreached.h"
#include "base/strings/sys_string_conversions.h"
#include "chrome/app/chrome_command_ids.h"
#include "chrome/browser/global_keyboard_shortcuts_mac.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/themes/theme_service.h"
#include "chrome/browser/ui/browser_active_state_manager/browser_active_state_manager.h"
#include "chrome/browser/ui/browser_command_controller.h"
#include "chrome/browser/ui/browser_commands.h"
#include "chrome/browser/ui/browser_init_state.h"
#include "chrome/browser/ui/browser_window/public/browser_collection.h"
#include "chrome/browser/ui/browser_window/public/browser_window_features.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#include "chrome/browser/ui/browser_window/public/global_browser_collection.h"
#include "chrome/browser/ui/find_bar/find_bar.h"
#include "chrome/browser/ui/location_bar/location_bar.h"
#include "chrome/browser/ui/tabs/tab_strip_model.h"
#include "chrome/browser/ui/unload_controller.h"
#include "chrome/browser/ui/views/bubble_anchor_util_views.h"
#include "chrome/browser/web_applications/web_app_helpers.h"
#include "components/input/native_web_keyboard_event.h"
#include "components/url_formatter/elide_url.h"
#include "content/public/browser/eye_dropper.h"
#include "content/public/browser/keyboard_event_processing_result.h"
#include "content/public/browser/web_contents.h"
#include "extensions/browser/extension_registry.h"
#include "extensions/common/constants.h"
#include "extensions/common/extension.h"
#include "extensions/common/manifest_handlers/icons_handler.h"
#include "fiber/browser/window/fiber_browser_window.h"
#import "ui/base/cocoa/cocoa_base_utils.h"
#include "ui/base/mojom/window_show_state.mojom.h"
#include "ui/color/color_provider_manager.h"
#include "ui/gfx/image/image_skia_util_mac.h"
#include "ui/gfx/mac/coordinate_conversion.h"
#include "ui/native_theme/native_theme.h"

// Forwards what the user does with an extension's window to its
// FiberExtensionWindow, and the main menu's commands while its page has focus.
@interface FiberExtensionWindowActionsBridge
    : NSObject <FiberExtensionWindowActions, NSUserInterfaceValidations>
- (instancetype)initWithOwner:(fiber::FiberExtensionWindow*)owner;
- (void)detachOwner;
@end

@implementation FiberExtensionWindowActionsBridge {
  raw_ptr<fiber::FiberExtensionWindow> _owner;
}

- (instancetype)initWithOwner:(fiber::FiberExtensionWindow*)owner {
  if ((self = [super init])) {
    _owner = owner;
  }
  return self;
}

- (void)detachOwner {
  _owner = nullptr;
}

- (void)extensionWindowShouldClose {
  if (_owner) {
    _owner->OnCloseRequested();
  }
}

- (void)extensionWindowDidExpand {
  if (_owner) {
    _owner->OnExpanded();
  }
}

- (void)extensionWindowDidBecomeActive {
  if (_owner) {
    _owner->OnActivationChanged(true);
  }
}

- (void)extensionWindowDidResignActive {
  if (_owner) {
    _owner->OnActivationChanged(false);
  }
}

// Chrome's main menu commands:

- (void)commandDispatch:(id)sender {
  if (_owner) {
    _owner->ExecuteCommand([sender tag], WindowOpenDisposition::CURRENT_TAB);
  }
}

- (void)commandDispatchUsingKeyModifiers:(id)sender {
  if (_owner) {
    _owner->ExecuteCommand(
        [sender tag], ui::WindowOpenDispositionFromNSEvent(NSApp.currentEvent));
  }
}

- (BOOL)validateUserInterfaceItem:(id<NSValidatedUserInterfaceItem>)item {
  if (item.action != @selector(commandDispatch:) &&
      item.action != @selector(commandDispatchUsingKeyModifiers:)) {
    return YES;
  }
  return _owner && _owner->IsCommandEnabled(item.tag);
}

@end

namespace fiber {

namespace {

// Rendered at up to twice this, in the bubble.
constexpr int kIconSize = 32;

std::vector<FiberExtensionWindow*>& AllWindows() {
  static base::NoDestructor<std::vector<FiberExtensionWindow*>> windows;
  return *windows;
}

// The extension whose own window `browser` is, if any.
const extensions::Extension* ExtensionFor(BrowserWindowInterface* browser) {
  if (browser->GetType() != BrowserWindowInterface::TYPE_APP_POPUP) {
    return nullptr;
  }
  const std::string id = web_app::GetAppIdFromApplicationName(
      BrowserInitState::From(browser)->create_params().app_name);
  const extensions::Extension* extension =
      extensions::ExtensionRegistry::Get(browser->GetProfile())
          ->enabled_extensions()
          .GetByID(id);
  // Not an app's (a hosted app's, say).
  return extension && extension->is_extension() ? extension : nullptr;
}

// windows.create() sizes a window by its frame, title bar included; the panel
// sizes the page.
int TitleBarHeight() {
  const NSRect content = NSMakeRect(0, 0, 100, 100);
  return NSHeight([NSWindow frameRectForContentRect:content
                                          styleMask:NSWindowStyleMaskTitled]) -
         NSHeight(content);
}

// Commands that act on the window's page, which run on its browser while the
// page has focus. The rest (a new tab, the command palette…) are the browser
// window's.
bool IsPageCommand(int command) {
  switch (command) {
    case IDC_BACK:
    case IDC_FORWARD:
    case IDC_RELOAD:
    case IDC_RELOAD_BYPASSING_CACHE:
    case IDC_RELOAD_CLEARING_CACHE:
    case IDC_STOP:
    case IDC_CLOSE_TAB:
    case IDC_CLOSE_WINDOW:
    case IDC_ZOOM_PLUS:
    case IDC_ZOOM_NORMAL:
    case IDC_ZOOM_MINUS:
    case IDC_DEV_TOOLS:
    case IDC_DEV_TOOLS_CONSOLE:
    case IDC_DEV_TOOLS_INSPECT:
    case IDC_DEV_TOOLS_TOGGLE:
      return true;
    default:
      return false;
  }
}

}  // namespace

// Chrome expects every window to have one. The panel shows the page's site
// instead, when it isn't the extension's.
class ExtensionWindowLocationBar : public LocationBar {
 public:
  explicit ExtensionWindowLocationBar(BrowserWindowInterface* browser)
      : LocationBar(chrome::BrowserCommandController::From(browser)),
        browser_(browser) {}

  // LocationBar:
  void FocusLocation(bool is_user_initiated,
                     bool clear_focus_if_failed) override {}
  void FocusSearch() override {}
  void UpdateFocusBehavior(bool toolbar_visible) override {}
  void UpdateContentSettingsIcons() override {}
  void SaveStateToContents(content::WebContents* contents) override {}
  void Revert() override {}
  OmniboxView* GetOmniboxView() override { return nullptr; }
  OmniboxPopupView* GetOmniboxPopupView() override { return nullptr; }
  OmniboxController* GetOmniboxController() override { return nullptr; }
  bool ShouldCloseOmniboxPopup(ui::MouseEvent* event) override { return false; }
  content::WebContents* GetWebContents() override {
    return browser_->GetTabStripModel()->GetActiveWebContents();
  }
  LocationBarModel* GetLocationBarModel() override {
    return browser_->GetFeatures().location_bar_model();
  }
  std::optional<bubble_anchor_util::AnchorConfiguration> GetChipAnchor()
      override {
    return std::nullopt;
  }
  ChipController* GetChipController() override { return nullptr; }
  void AnnounceAlert(const std::u16string& announcement) override {}
  void OnChanged() override {}
  void UpdateWithoutTabRestore() override {}
  ui::TrackedElement* GetAnchorOrNull() override { return nullptr; }
  BrowserWindowInterface* GetBrowser() override { return browser_; }
  Profile* GetProfile() override { return browser_->GetProfile(); }
  bool IsInitialized() const override { return true; }
  bool IsVisible() const override { return false; }
  bool IsDrawn() const override { return false; }
  bool IsFullscreen() const override { return false; }
  bool IsEditingOrEmpty() const override { return false; }
  bool IsMouseHovered() const override { return false; }
  bool IsFocusWithin() const override { return false; }
  void InvalidateLayout() override {}
  gfx::Rect Bounds() const override { return gfx::Rect(); }
  gfx::Rect BoundsInScreen() const override { return gfx::Rect(); }
  gfx::Size MinimumSize() const override { return gfx::Size(); }
  gfx::Size PreferredSize() const override { return gfx::Size(); }
  void Update(content::WebContents* contents) override {}
  void ResetTabState(content::WebContents* contents) override {}
  bool HasSecurityStateChanged() override { return false; }
  LocationBarTesting* GetLocationBarForTesting() override { return nullptr; }

 private:
  const raw_ptr<BrowserWindowInterface> browser_;
};

// static
bool FiberExtensionWindow::IsExtensionWindow(BrowserWindowInterface* browser) {
  return ExtensionFor(browser) != nullptr;
}

// static
FiberBrowserWindow* FiberExtensionWindow::HostFor(
    BrowserWindowInterface* browser) {
  FiberBrowserWindow* host = nullptr;
  GlobalBrowserCollection::GetInstance()->ForEach(
      [&](BrowserWindowInterface* other) {
        if (other->GetProfile() == browser->GetProfile() &&
            !other->IsDeleteScheduled()) {
          host = FiberBrowserWindow::FromBrowser(other);
        }
        return !host;
      },
      BrowserCollection::Order::kActivation);
  return host;
}

// static
bool FiberExtensionWindow::IsActiveOver(const FiberBrowserWindow* host) {
  return std::ranges::any_of(AllWindows(),
                             [host](FiberExtensionWindow* window) {
                               return window->active_ && window->host() == host;
                             });
}

// static
FiberExtensionWindow* FiberExtensionWindow::FromBrowser(
    BrowserWindowInterface* browser) {
  BrowserWindow* window =
      browser ? BrowserWindow::FromBrowser(browser) : nullptr;
  for (FiberExtensionWindow* extension_window : AllWindows()) {
    if (extension_window == window) {
      return extension_window;
    }
  }
  return nullptr;
}

FiberExtensionWindow::FiberExtensionWindow(BrowserWindowInterface* browser,
                                           FiberBrowserWindow* host)
    : browser_(browser),
      extension_id_(ExtensionFor(browser)->id()),
      host_(host->GetWeakPtr()),
      actions_([[FiberExtensionWindowActionsBridge alloc] initWithOwner:this]),
      location_bar_(std::make_unique<ExtensionWindowLocationBar>(browser)) {
  AllWindows().push_back(this);
  ui_ = host->AddExtensionWindow(actions_);
  const extensions::Extension* extension = ExtensionFor(browser_);
  [ui_ setTitle:base::SysUTF8ToNSString(extension->name())];
  icon_ = std::make_unique<extensions::IconImage>(
      browser_->GetProfile(), extension,
      extensions::IconsInfo::GetIcons(extension), kIconSize, gfx::ImageSkia(),
      this);
  // It loads once asked for, and then tells this.
  icon_->image_skia().EnsureRepsForSupportedScales();
  const gfx::Size frame_size =
      BrowserInitState::From(browser_)->create_params().initial_bounds.size();
  SetContentsSize(gfx::Size(
      frame_size.width(), std::max(frame_size.height() - TitleBarHeight(), 0)));
  host_did_close_subscription_ =
      host->browser()->RegisterBrowserDidClose(base::BindRepeating(
          &FiberExtensionWindow::OnHostDidClose, base::Unretained(this)));
}

FiberExtensionWindow::~FiberExtensionWindow() {
  std::erase(AllWindows(), this);
  browser_->GetFeatures().TearDownPreBrowserWindowDestruction();
  Observe(nullptr);
  [actions_ detachOwner];
  [ui_ close];
}

void FiberExtensionWindow::DeleteBrowserWindow() {
  delete this;
}

void FiberExtensionWindow::OnCloseRequested() {
  Close();
}

void FiberExtensionWindow::OnExpanded() {
  FocusPage();
}

void FiberExtensionWindow::OnActivationChanged(bool active) {
  active_ = active;
  // As FiberBrowserWindow::OnWindowActivationChanged().
  if (active && browser_->IsDeleteScheduled()) {
    return;
  }
  if (active) {
    BrowserActiveStateManager::From(browser_)->DidBecomeActive();
  } else {
    BrowserActiveStateManager::From(browser_)->DidBecomeInactive();
  }
}

void FiberExtensionWindow::ExecuteCommand(int command,
                                          WindowOpenDisposition disposition) {
  if (!IsPageCommand(command)) {
    if (host_) {
      host_->ExecuteCommand(command, disposition);
    }
    return;
  }
  if (chrome::IsCommandEnabled(browser_, command)) {
    chrome::ExecuteCommandWithDisposition(browser_, command, disposition);
  }
}

bool FiberExtensionWindow::IsCommandEnabled(int command) const {
  if (!IsPageCommand(command)) {
    return host_ && host_->IsCommandEnabled(command);
  }
  return chrome::IsCommandEnabled(browser_, command);
}

content::WebContents* FiberExtensionWindow::GetActiveWebContents() const {
  return browser_->GetTabStripModel()->GetActiveWebContents();
}

void FiberExtensionWindow::OnHostDidClose(BrowserWindowInterface* host) {
  Close();
}

void FiberExtensionWindow::UpdateSite() {
  content::WebContents* contents = GetActiveWebContents();
  const GURL url = contents ? contents->GetLastCommittedURL() : GURL();
  const bool is_own =
      url.SchemeIs(extensions::kExtensionScheme) && url.host() == extension_id_;
  [ui_ setSite:url.is_empty() || is_own
                   ? @""
                   : base::SysUTF16ToNSString(
                         url_formatter::FormatUrlForSecurityDisplay(
                             url, url_formatter::SchemeDisplay::
                                      OMIT_HTTP_AND_HTTPS))];
}

void FiberExtensionWindow::FocusPage() {
  if (content::WebContents* contents = GetActiveWebContents()) {
    contents->Focus();
  }
}

// BrowserWindow:

gfx::NativeWindow FiberExtensionWindow::GetNativeWindow() const {
  // The browser window's, which dialogs for the page go over.
  return host_ ? host_->GetNativeWindow() : gfx::NativeWindow();
}

bool FiberExtensionWindow::IsOnCurrentWorkspace() const {
  return host_ && host_->IsOnCurrentWorkspace();
}

bool FiberExtensionWindow::IsVisibleOnScreen() const {
  return !IsMinimized() && host_ && host_->IsVisibleOnScreen();
}

void FiberExtensionWindow::SetTopControlsShownRatio(
    content::WebContents* web_contents,
    float ratio) {}

bool FiberExtensionWindow::DoBrowserControlsShrinkRendererSize(
    const content::WebContents* contents) const {
  return false;
}

ui::NativeTheme* FiberExtensionWindow::GetNativeTheme() {
  return ui::NativeTheme::GetInstanceForNativeUi();
}

const ui::ThemeProvider* FiberExtensionWindow::GetThemeProvider() const {
  return &ThemeService::GetThemeProviderForProfile(browser_->GetProfile());
}

const ui::ColorProvider* FiberExtensionWindow::GetColorProvider() const {
  return ui::ColorProviderManager::Get().GetColorProviderFor(
      ui::NativeTheme::GetInstanceForNativeUi()->GetColorProviderKey(
          /*custom_theme=*/nullptr));
}

int FiberExtensionWindow::GetTopControlsHeight() const {
  return 0;
}

void FiberExtensionWindow::SetTopControlsGestureScrollInProgress(
    bool in_progress) {}

std::vector<StatusBubble*> FiberExtensionWindow::GetStatusBubbles() {
  return {};
}

void FiberExtensionWindow::UpdateTitleBar() {}

void FiberExtensionWindow::UpdateLoadingAnimations(bool is_visible) {}

void FiberExtensionWindow::OnActiveTabChanged(
    content::WebContents* old_contents,
    content::WebContents* new_contents,
    int index,
    int reason) {
  [ui_ setContentsView:new_contents->GetNativeView().GetNativeNSView()];
  if (host_) {
    new_contents->SetColorProviderSource(host_.get());
  }
  Observe(new_contents);
  UpdateSite();
}

void FiberExtensionWindow::OnTabDetached(content::WebContents* contents,
                                         bool was_active) {
  if (was_active) {
    [ui_ setContentsView:nil];
    Observe(nullptr);
  }
}

gfx::Size FiberExtensionWindow::GetContentsSize() const {
  return contents_size_;
}

void FiberExtensionWindow::SetContentsSize(const gfx::Size& size) {
  contents_size_ = size;
  [ui_ setContentSize:NSMakeSize(size.width(), size.height())];
}

autofill::AutofillBubbleHandler*
FiberExtensionWindow::GetAutofillBubbleHandler() {
  return nullptr;
}

LocationBar* FiberExtensionWindow::GetLocationBar() const {
  return location_bar_.get();
}

ui::AcceleratorProvider* FiberExtensionWindow::GetAcceleratorProvider() {
  return this;
}

void FiberExtensionWindow::SetFocusToLocationBar(bool is_user_initiated) {}

void FiberExtensionWindow::UpdateReloadStopState(bool is_loading, bool force) {}

void FiberExtensionWindow::UpdateToolbar(content::WebContents* contents) {}

bool FiberExtensionWindow::UpdateToolbarSecurityState() {
  return false;
}

void FiberExtensionWindow::UpdateCustomTabBarVisibility(bool visible,
                                                        bool animate) {}

void FiberExtensionWindow::ResetToolbarTabState(
    content::WebContents* contents) {}

void FiberExtensionWindow::FocusToolbar() {}

void FiberExtensionWindow::ToolbarSizeChanged(bool is_animating) {}

void FiberExtensionWindow::TabDraggingStatusChanged(bool is_dragging) {}

void FiberExtensionWindow::LinkOpeningFromGesture(
    WindowOpenDisposition disposition) {}

void FiberExtensionWindow::FocusAppMenu() {}

bool FiberExtensionWindow::IsTabStripEditable() const {
  return false;
}

void FiberExtensionWindow::DisableTabStripEditingForTesting() {}

bool FiberExtensionWindow::IsToolbarVisible() const {
  return false;
}

bool FiberExtensionWindow::IsToolbarShowing() const {
  return false;
}

bool FiberExtensionWindow::IsLocationBarVisible() const {
  return false;
}

void FiberExtensionWindow::ShowUpdateChromeDialog() {}

void FiberExtensionWindow::ShowIntentPickerBubble(
    std::vector<apps::IntentPickerAppInfo> app_info,
    bool show_stay_in_chrome,
    bool show_remember_selection,
    apps::IntentPickerBubbleType bubble_type,
    const std::optional<url::Origin>& initiating_origin,
    IntentPickerResponse callback) {}

void FiberExtensionWindow::ShowBookmarkBubble(const GURL& url,
                                              bool already_bookmarked) {}

ShowTranslateBubbleResult FiberExtensionWindow::ShowTranslateBubble(
    content::WebContents* contents,
    translate::TranslateStep step,
    const std::string& source_language,
    const std::string& target_language,
    translate::TranslateErrors error_type,
    bool is_user_gesture) {
  return ShowTranslateBubbleResult::kBrowserWindowNotValid;
}

DownloadBubbleUIController*
FiberExtensionWindow::GetDownloadBubbleUIController() {
  return nullptr;
}

void FiberExtensionWindow::ConfirmBrowserCloseWithPendingDownloads(
    int download_count,
    DownloadCloseType dialog_type,
    base::OnceCallback<void(bool)> callback) {
  // Its profile's downloads wait on the browser window's close, not this.
  std::move(callback).Run(true);
}

void FiberExtensionWindow::ShowAppMenu() {}

void FiberExtensionWindow::PreHandleDragUpdate(
    const content::DropData& drop_data,
    const gfx::PointF& point) {}

void FiberExtensionWindow::PreHandleDragExit() {}

void FiberExtensionWindow::HandleDragEnded() {}

content::KeyboardEventProcessingResult
FiberExtensionWindow::PreHandleKeyboardEvent(
    const input::NativeWebKeyboardEvent& event) {
  return content::KeyboardEventProcessingResult::NOT_HANDLED;
}

bool FiberExtensionWindow::HandleKeyboardEvent(
    const input::NativeWebKeyboardEvent& event) {
  // As FiberBrowserWindow: keys the page didn't handle go to the main menu,
  // whose commands come to this window's actions while its page has focus.
  if (event.skip_if_unhandled ||
      event.GetType() == input::NativeWebKeyboardEvent::Type::kChar) {
    return false;
  }
  NSEvent* ns_event = event.os_event.Get();
  return ns_event.type == NSEventTypeKeyDown &&
         [NSApp.mainMenu performKeyEquivalent:ns_event];
}

std::unique_ptr<FindBar> FiberExtensionWindow::CreateFindBar() {
  // Unreachable: IDC_FIND goes to the browser window's.
  NOTREACHED();
}

web_modal::WebContentsModalDialogHost*
FiberExtensionWindow::GetWebContentsModalDialogHost() {
  return nullptr;
}

web_modal::WebContentsModalDialogHost*
FiberExtensionWindow::GetWebContentsModalDialogHostFor(
    content::WebContents* web_contents) {
  return nullptr;
}

void FiberExtensionWindow::ShowAvatarBubbleFromAvatarButton(
    bool is_source_accelerator) {}

void FiberExtensionWindow::MaybeShowProfileSwitchIPH() {}

void FiberExtensionWindow::MaybeShowSupervisedUserProfileSignInIPH() {}

void FiberExtensionWindow::ShowHatsDialog(
    const std::string& site_id,
    const std::optional<std::string>& hats_histogram_name,
    const std::optional<uint64_t> hats_survey_ukm_id,
    base::OnceClosure success_callback,
    base::OnceClosure failure_callback,
    const SurveyBitsData& product_specific_bits_data,
    const SurveyStringData& product_specific_string_data) {
  std::move(failure_callback).Run();
}

ExclusiveAccessContext* FiberExtensionWindow::GetExclusiveAccessContext() {
  return this;
}

std::string FiberExtensionWindow::GetWorkspace() const {
  return std::string();
}

bool FiberExtensionWindow::IsVisibleOnAllWorkspaces() const {
  return false;
}

void FiberExtensionWindow::ShowEmojiPanel() {
  [NSApp orderFrontCharacterPalette:nil];
}

std::unique_ptr<content::EyeDropper> FiberExtensionWindow::OpenEyeDropper(
    content::RenderFrameHost* frame,
    content::EyeDropperListener* listener) {
  return nullptr;
}

void FiberExtensionWindow::ShowCaretBrowsingDialog() {}

void FiberExtensionWindow::CreateTabSearchBubble() {}

void FiberExtensionWindow::CloseTabSearchBubble() {}

void FiberExtensionWindow::ShowIncognitoClearBrowsingDataDialog() {}

void FiberExtensionWindow::ShowIncognitoHistoryDisclaimerDialog() {}

bool FiberExtensionWindow::IsUnframedModeEnabled() const {
  return false;
}

bool FiberExtensionWindow::GetCanResize() {
  return true;
}

ui::mojom::WindowShowState FiberExtensionWindow::GetWindowShowState() const {
  return IsMinimized() ? ui::mojom::WindowShowState::kMinimized
                       : ui::mojom::WindowShowState::kDefault;
}

void FiberExtensionWindow::ShowChromeLabs() {}

BrowserView* FiberExtensionWindow::AsBrowserView() {
  return nullptr;
}

// ui::BaseWindow:

void FiberExtensionWindow::Show() {
  // Like FiberBrowserWindow::Show(): the browser counts as the last active one
  // as soon as this returns.
  BrowserActiveStateManager::From(browser_)->DidBecomeActive();
  Activate();
}

void FiberExtensionWindow::ShowInactive() {
  shown_ = true;
  [ui_ collapse];
}

void FiberExtensionWindow::Hide() {
  [ui_ collapse];
}

bool FiberExtensionWindow::IsVisible() const {
  return shown_;
}

void FiberExtensionWindow::SetBounds(const gfx::Rect& bounds) {
  // Only the size: the bubble stays where the user put it.
  SetContentsSize(gfx::Size(bounds.width(),
                            std::max(bounds.height() - TitleBarHeight(), 0)));
}

void FiberExtensionWindow::Close() {
  // As FiberBrowserWindow::Close(): unload handlers may stop the close, and
  // otherwise the Browser calls this again once its tab is gone.
  UnloadController* unload_controller = UnloadController::From(browser_);
  if (!unload_controller->HandleBeforeClose()) {
    return;
  }
  unload_controller->OnWindowClosing();
  shown_ = false;
  [ui_ close];
}

void FiberExtensionWindow::Activate() {
  shown_ = true;
  [ui_ expand];
  if (host_) {
    host_->Activate();
  }
  FocusPage();
}

void FiberExtensionWindow::Deactivate() {}

bool FiberExtensionWindow::IsActive() const {
  return active_;
}

gfx::Rect FiberExtensionWindow::GetBounds() const {
  NSRect frame = ui_.pageFrame;
  frame.size.height += TitleBarHeight();
  return gfx::ScreenRectFromNSRect(frame);
}

bool FiberExtensionWindow::IsMaximized() const {
  return false;
}

bool FiberExtensionWindow::IsMinimized() const {
  return shown_ && !ui_.isExpanded;
}

bool FiberExtensionWindow::IsFullscreen() const {
  return false;
}

gfx::Rect FiberExtensionWindow::GetRestoredBounds() const {
  return GetBounds();
}

ui::mojom::WindowShowState FiberExtensionWindow::GetRestoredState() const {
  return ui::mojom::WindowShowState::kDefault;
}

void FiberExtensionWindow::Maximize() {}

void FiberExtensionWindow::Minimize() {
  [ui_ collapse];
}

void FiberExtensionWindow::Restore() {
  [ui_ expand];
}

void FiberExtensionWindow::FlashFrame(bool flash) {}

ui::ZOrderLevel FiberExtensionWindow::GetZOrderLevel() const {
  return ui::ZOrderLevel::kNormal;
}

void FiberExtensionWindow::SetZOrderLevel(ui::ZOrderLevel order) {}

// ExclusiveAccessContext:

Profile* FiberExtensionWindow::GetProfile() {
  return browser_->GetProfile();
}

void FiberExtensionWindow::EnterFullscreen(
    const url::Origin& origin,
    ExclusiveAccessBubbleType bubble_type,
    FullscreenTabParams fullscreen_tab_params) {}

void FiberExtensionWindow::ExitFullscreen() {}

void FiberExtensionWindow::UpdateExclusiveAccessBubble(
    const ExclusiveAccessBubbleParams& params,
    ExclusiveAccessBubbleHideCallback first_hide_callback) {}

bool FiberExtensionWindow::IsExclusiveAccessBubbleDisplayed() const {
  return false;
}

void FiberExtensionWindow::OnExclusiveAccessUserInput() {}

content::WebContents* FiberExtensionWindow::GetWebContentsForExclusiveAccess() {
  // None: a page in a bubble can't go fullscreen or lock the pointer, and
  // Chrome turns it down rather than leave it waiting.
  return nullptr;
}

bool FiberExtensionWindow::CanUserEnterFullscreen() const {
  return false;
}

bool FiberExtensionWindow::CanUserExitFullscreen() const {
  return true;
}

// ui::AcceleratorProvider:

bool FiberExtensionWindow::GetAcceleratorForCommandId(
    int command_id,
    ui::Accelerator* accelerator) const {
  return GetDefaultMacAcceleratorForCommandId(command_id, accelerator);
}

// extensions::IconImage::Observer:

void FiberExtensionWindow::OnExtensionIconImageChanged(
    extensions::IconImage* image) {
  [ui_ setIcon:gfx::NSImageFromImageSkia(image->image_skia())];
}

// content::WebContentsObserver:

void FiberExtensionWindow::PrimaryPageChanged(content::Page& page) {
  UpdateSite();
}

}  // namespace fiber
