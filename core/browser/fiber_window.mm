#include "fiber/browser/fiber_window.h"

#import <Cocoa/Cocoa.h>

#include <string_view>
#include <vector>

#include "base/functional/bind.h"
#include "base/no_destructor.h"
#include "base/strings/escape.h"
#include "base/strings/string_util.h"
#include "base/strings/sys_string_conversions.h"
#include "base/task/single_thread_task_runner.h"
#include "chrome/app/chrome_command_ids.h"
#include "chrome/browser/profiles/keep_alive/profile_keep_alive_types.h"
#include "chrome/browser/profiles/profile.h"
#include "components/input/native_web_keyboard_event.h"
#include "components/url_formatter/url_fixer.h"
#include "content/public/browser/navigation_controller.h"
#include "content/public/browser/navigation_handle.h"
#include "content/public/browser/page_navigator.h"
#include "content/public/browser/reload_type.h"
#include "content/public/browser/web_contents.h"
#include "ui/base/page_transition_types.h"
#include "ui/base/window_open_disposition.h"
#include "url/gurl.h"

namespace {

constexpr CGFloat kToolbarHeight = 38;
constexpr NSSize kDefaultWindowSize = {1280, 820};
constexpr char kSearchURLPrefix[] = "https://www.google.com/search?q=";

std::vector<fiber::FiberWindow*>& AllWindows() {
  static base::NoDestructor<std::vector<fiber::FiberWindow*>> windows;
  return *windows;
}

// Treats input as a URL when it plausibly is one, otherwise as a search query.
// TODO: Use the profile's default search engine and Chrome's autocomplete
// classifier instead of these heuristics.
GURL URLFromInput(std::string_view raw_input) {
  const std::string input(base::TrimWhitespaceASCII(raw_input, base::TRIM_ALL));
  if (input.empty()) {
    return GURL();
  }
  const bool looks_like_url =
      input.find(' ') == std::string::npos &&
      (input.find('.') != std::string::npos ||
       input.find(':') != std::string::npos || input == "localhost");
  if (looks_like_url) {
    GURL url = url_formatter::FixupURL(input);
    if (url.is_valid()) {
      return url;
    }
  }
  return GURL(kSearchURLPrefix +
              base::EscapeQueryParamValue(input, /*use_plus=*/true));
}

}  // namespace

// Owns the NSWindow and its toolbar, and forwards UI events to FiberWindow.
@interface FiberWindowController
    : NSObject <NSWindowDelegate, NSUserInterfaceValidations>
@property(readonly, nonatomic) NSWindow* window;
- (instancetype)initWithOwner:(fiber::FiberWindow*)owner;
- (void)setWebContentsView:(NSView*)view;
- (void)updateWithURL:(NSString*)url
                title:(NSString*)title
            canGoBack:(BOOL)canGoBack
         canGoForward:(BOOL)canGoForward
            isLoading:(BOOL)isLoading;
- (void)focusLocationBar;
// Called by the owner when it is being destroyed.
- (void)detachOwner;
@end

@implementation FiberWindowController {
  raw_ptr<fiber::FiberWindow> _owner;
  NSWindow* __strong _window;
  NSButton* __strong _backButton;
  NSButton* __strong _forwardButton;
  NSButton* __strong _reloadButton;
  NSTextField* __strong _locationField;
  NSView* __strong _contentArea;
}

@synthesize window = _window;

- (instancetype)initWithOwner:(fiber::FiberWindow*)owner {
  if ((self = [super init])) {
    _owner = owner;

    _window = [[NSWindow alloc]
        initWithContentRect:NSMakeRect(0, 0, kDefaultWindowSize.width,
                                       kDefaultWindowSize.height)
                  styleMask:NSWindowStyleMaskTitled |
                            NSWindowStyleMaskClosable |
                            NSWindowStyleMaskMiniaturizable |
                            NSWindowStyleMaskResizable
                    backing:NSBackingStoreBuffered
                      defer:NO];
    _window.releasedWhenClosed = NO;
    _window.delegate = self;
    _window.minSize = NSMakeSize(480, 320);
    _window.title = @"Fiber";

    NSView* content = _window.contentView;
    const NSRect bounds = content.bounds;

    _backButton = [self toolbarButtonWithSymbol:@"chevron.backward"
                                          label:@"Back"
                                         action:@selector(goBack:)];
    _forwardButton = [self toolbarButtonWithSymbol:@"chevron.forward"
                                             label:@"Forward"
                                            action:@selector(goForward:)];
    _reloadButton = [self toolbarButtonWithSymbol:@"arrow.clockwise"
                                            label:@"Reload"
                                           action:@selector(reloadOrStop:)];

    _locationField = [NSTextField textFieldWithString:@""];
    _locationField.placeholderString = @"Search or enter address";
    _locationField.bezelStyle = NSTextFieldRoundedBezel;
    _locationField.target = self;
    _locationField.action = @selector(navigateToLocation:);
    _locationField.cell.sendsActionOnEndEditing = NO;
    _locationField.cell.scrollable = YES;
    [_locationField
        setContentHuggingPriority:NSLayoutPriorityDefaultLow
                   forOrientation:NSLayoutConstraintOrientationHorizontal];

    NSStackView* toolbar = [NSStackView stackViewWithViews:@[
      _backButton, _forwardButton, _reloadButton, _locationField
    ]];
    toolbar.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    toolbar.alignment = NSLayoutAttributeCenterY;
    toolbar.spacing = 4;
    toolbar.edgeInsets = NSEdgeInsetsMake(0, 8, 0, 10);
    toolbar.frame = NSMakeRect(0, NSHeight(bounds) - kToolbarHeight,
                               NSWidth(bounds), kToolbarHeight);
    toolbar.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin;
    [content addSubview:toolbar];

    NSBox* separator = [[NSBox alloc]
        initWithFrame:NSMakeRect(0, NSHeight(bounds) - kToolbarHeight - 1,
                                 NSWidth(bounds), 1)];
    separator.boxType = NSBoxSeparator;
    separator.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin;
    [content addSubview:separator];

    _contentArea = [[NSView alloc]
        initWithFrame:NSMakeRect(0, 0, NSWidth(bounds),
                                 NSHeight(bounds) - kToolbarHeight - 1)];
    _contentArea.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [content addSubview:_contentArea];

    [_window center];
  }
  return self;
}

- (NSButton*)toolbarButtonWithSymbol:(NSString*)symbol
                               label:(NSString*)label
                              action:(SEL)action {
  NSButton* button = [NSButton
      buttonWithImage:[NSImage imageWithSystemSymbolName:symbol
                                accessibilityDescription:label]
               target:self
               action:action];
  button.bordered = NO;
  button.toolTip = label;
  [button.widthAnchor constraintEqualToConstant:28].active = YES;
  return button;
}

- (void)setWebContentsView:(NSView*)view {
  view.frame = _contentArea.bounds;
  view.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
  [_contentArea addSubview:view];
}

- (void)updateWithURL:(NSString*)url
                title:(NSString*)title
            canGoBack:(BOOL)canGoBack
         canGoForward:(BOOL)canGoForward
            isLoading:(BOOL)isLoading {
  _window.title = title.length ? title : @"Fiber";
  // Don't clobber what the user is typing.
  if (!_locationField.currentEditor) {
    _locationField.stringValue = url;
  }
  _backButton.enabled = canGoBack;
  _forwardButton.enabled = canGoForward;
  NSString* reloadLabel = isLoading ? @"Stop" : @"Reload";
  _reloadButton.image = [NSImage
      imageWithSystemSymbolName:isLoading ? @"xmark" : @"arrow.clockwise"
       accessibilityDescription:reloadLabel];
  _reloadButton.toolTip = reloadLabel;
}

- (void)focusLocationBar {
  [_window makeFirstResponder:_locationField];
}

- (void)detachOwner {
  _owner = nullptr;
}

// Toolbar actions.

- (void)goBack:(id)sender {
  if (_owner) {
    _owner->GoBack();
  }
}

- (void)goForward:(id)sender {
  if (_owner) {
    _owner->GoForward();
  }
}

- (void)reloadOrStop:(id)sender {
  if (_owner) {
    _owner->ReloadOrStop();
  }
}

- (void)navigateToLocation:(id)sender {
  if (_owner) {
    _owner->NavigateToInput(base::SysNSStringToUTF8(_locationField.stringValue));
  }
}

// Chrome's main menu sends -commandDispatch: with the command ID as the tag.
// As the window delegate we're in the responder chain ahead of Chrome's
// AppController, so menu items act on this window while it's key.

- (void)commandDispatch:(id)sender {
  if (!_owner) {
    return;
  }
  switch ([sender tag]) {
    case IDC_BACK:
      _owner->GoBack();
      break;
    case IDC_FORWARD:
      _owner->GoForward();
      break;
    case IDC_RELOAD:
    case IDC_STOP:
      _owner->ReloadOrStop();
      break;
    case IDC_FOCUS_LOCATION:
      [self focusLocationBar];
      break;
    case IDC_NEW_TAB:
    case IDC_NEW_WINDOW:
      _owner->NewWindow();
      break;
    case IDC_CLOSE_TAB:
    case IDC_CLOSE_WINDOW:
      _owner->Close();
      break;
  }
}

- (BOOL)validateUserInterfaceItem:(id<NSValidatedUserInterfaceItem>)item {
  if (item.action != @selector(commandDispatch:)) {
    return YES;
  }
  switch (item.tag) {
    case IDC_BACK:
      return _backButton.enabled;
    case IDC_FORWARD:
      return _forwardButton.enabled;
    case IDC_RELOAD:
    case IDC_STOP:
    case IDC_FOCUS_LOCATION:
    case IDC_NEW_TAB:
    case IDC_NEW_WINDOW:
    case IDC_CLOSE_TAB:
    case IDC_CLOSE_WINDOW:
      return YES;
    default:
      // Everything else in Chrome's menus assumes a Chrome Browser window.
      return NO;
  }
}

// NSWindowDelegate:

- (void)windowWillClose:(NSNotification*)notification {
  if (_owner) {
    _owner->OnNativeWindowClosing();
  }
}

@end

namespace fiber {

// static
FiberWindow* FiberWindow::Create(Profile* profile, const GURL& url) {
  FiberWindow* window = CreateWithContents(
      profile, content::WebContents::Create(
                   content::WebContents::CreateParams(profile)));
  if (url.is_valid()) {
    window->LoadURL(url);
    window->web_contents_->Focus();
  } else {
    [window->controller_ focusLocationBar];
  }
  return window;
}

// static
FiberWindow* FiberWindow::CreateWithContents(
    Profile* profile,
    std::unique_ptr<content::WebContents> web_contents) {
  return new FiberWindow(profile, std::move(web_contents));
}

// static
void FiberWindow::CloseAll() {
  // Copy, since each deletion removes itself from the list.
  const std::vector<FiberWindow*> windows = AllWindows();
  for (FiberWindow* window : windows) {
    delete window;
  }
}

FiberWindow::FiberWindow(Profile* profile,
                         std::unique_ptr<content::WebContents> web_contents)
    : profile_(profile),
      profile_keep_alive_(profile, ProfileKeepAliveOrigin::kBrowserWindow),
      web_contents_(std::move(web_contents)),
      controller_([[FiberWindowController alloc] initWithOwner:this]) {
  AllWindows().push_back(this);
  web_contents_->SetDelegate(this);
  [controller_
      setWebContentsView:web_contents_->GetNativeView().GetNativeNSView()];
  UpdateToolbar();
  [controller_.window makeKeyAndOrderFront:nil];
}

FiberWindow::~FiberWindow() {
  std::erase(AllWindows(), this);
  [controller_ detachOwner];
  web_contents_->SetDelegate(nullptr);
  web_contents_.reset();
  // No-op if the user already closed it.
  [controller_.window close];
}

void FiberWindow::NavigateToInput(const std::string& input) {
  const GURL url = URLFromInput(input);
  if (!url.is_valid()) {
    return;
  }
  LoadURL(url);
  web_contents_->Focus();
}

void FiberWindow::GoBack() {
  if (web_contents_->GetController().CanGoBack()) {
    web_contents_->GetController().GoBack();
  }
}

void FiberWindow::GoForward() {
  if (web_contents_->GetController().CanGoForward()) {
    web_contents_->GetController().GoForward();
  }
}

void FiberWindow::ReloadOrStop() {
  if (web_contents_->IsLoading()) {
    web_contents_->Stop();
  } else {
    web_contents_->GetController().Reload(content::ReloadType::NORMAL,
                                          /*check_for_repost=*/true);
  }
}

void FiberWindow::NewWindow() {
  Create(profile_, GURL());
}

void FiberWindow::Close() {
  [controller_.window close];
}

void FiberWindow::OnNativeWindowClosing() {
  // Deleting synchronously isn't safe here: this can run inside AppKit's close
  // sequence or a WebContents callback (window.close()).
  base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(
      FROM_HERE,
      base::BindOnce(&FiberWindow::Destroy, weak_factory_.GetWeakPtr()));
}

content::WebContents* FiberWindow::OpenURLFromTab(
    content::WebContents* source,
    const content::OpenURLParams& params,
    base::OnceCallback<void(content::NavigationHandle&)>
        navigation_handle_callback) {
  content::WebContents* target = nullptr;
  switch (params.disposition) {
    case WindowOpenDisposition::CURRENT_TAB:
      target = source;
      break;
    // No tabs yet, so anything tab- or window-shaped gets a new window.
    case WindowOpenDisposition::NEW_FOREGROUND_TAB:
    case WindowOpenDisposition::NEW_BACKGROUND_TAB:
    case WindowOpenDisposition::NEW_POPUP:
    case WindowOpenDisposition::NEW_WINDOW:
      target = Create(profile_, GURL())->web_contents();
      break;
    default:
      return nullptr;
  }

  base::WeakPtr<content::NavigationHandle> navigation_handle =
      target->GetController().LoadURLWithParams(
          content::NavigationController::LoadURLParams(params));
  if (navigation_handle_callback && navigation_handle) {
    std::move(navigation_handle_callback).Run(*navigation_handle);
  }
  return target;
}

content::WebContents* FiberWindow::AddNewContents(
    content::WebContents* source,
    std::unique_ptr<content::WebContents> new_contents,
    const GURL& target_url,
    WindowOpenDisposition disposition,
    const blink::mojom::WindowFeatures& window_features,
    bool user_gesture,
    bool* was_blocked) {
  return CreateWithContents(profile_, std::move(new_contents))->web_contents();
}

void FiberWindow::NavigationStateChanged(
    content::WebContents* source,
    content::InvalidateTypes changed_flags) {
  UpdateToolbar();
}

void FiberWindow::LoadingStateChanged(content::WebContents* source,
                                      bool should_show_loading_ui) {
  UpdateToolbar();
}

void FiberWindow::CloseContents(content::WebContents* source) {
  Close();
}

bool FiberWindow::HandleKeyboardEvent(
    content::WebContents* source,
    const input::NativeWebKeyboardEvent& event) {
  // Keys go to the page first; give unhandled ones to the menus so shortcuts
  // like Cmd-L work while the page has focus.
  if (event.skip_if_unhandled) {
    return false;
  }
  NSEvent* ns_event = event.os_event.Get();
  return ns_event.type == NSEventTypeKeyDown &&
         [NSApp.mainMenu performKeyEquivalent:ns_event];
}

void FiberWindow::LoadURL(const GURL& url) {
  content::NavigationController::LoadURLParams params(url);
  params.transition_type = ui::PageTransitionFromInt(
      ui::PAGE_TRANSITION_TYPED | ui::PAGE_TRANSITION_FROM_ADDRESS_BAR);
  web_contents_->GetController().LoadURLWithParams(params);
}

void FiberWindow::UpdateToolbar() {
  content::NavigationController& controller = web_contents_->GetController();
  const GURL& url = web_contents_->GetVisibleURL();
  [controller_
      updateWithURL:url.is_empty() ? @"" : base::SysUTF8ToNSString(url.spec())
              title:base::SysUTF16ToNSString(web_contents_->GetTitle())
          canGoBack:controller.CanGoBack()
       canGoForward:controller.CanGoForward()
          isLoading:web_contents_->IsLoading()];
}

void FiberWindow::Destroy() {
  delete this;
}

}  // namespace fiber
