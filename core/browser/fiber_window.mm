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
#include "chrome/browser/profiles/keep_alive/profile_keep_alive_types.h"
#include "chrome/browser/profiles/profile.h"
#include "components/input/native_web_keyboard_event.h"
#include "components/url_formatter/elide_url.h"
#include "components/url_formatter/url_fixer.h"
#include "components/url_formatter/url_formatter.h"
#include "content/public/browser/navigation_controller.h"
#include "content/public/browser/navigation_handle.h"
#include "content/public/browser/page_navigator.h"
#include "content/public/browser/reload_type.h"
#include "content/public/browser/web_contents.h"
#import "fiber/browser/fiber_window_controller.h"
#include "ui/base/page_transition_types.h"
#include "ui/base/window_open_disposition.h"
#include "url/gurl.h"

namespace {

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
  Observe(web_contents_.get());
  [controller_
      setWebContentsView:web_contents_->GetNativeView().GetNativeNSView()];
  UpdateToolbar();
  [controller_.window makeKeyAndOrderFront:nil];
}

FiberWindow::~FiberWindow() {
  std::erase(AllWindows(), this);
  [controller_ detachOwner];
  Observe(nullptr);
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

void FiberWindow::FocusWebContents() {
  web_contents_->Focus();
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
  UpdateLoadProgress();
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

void FiberWindow::UpdateTargetURL(content::WebContents* source,
                                  const GURL& url) {
  [controller_ setStatusText:url.is_empty() ? @""
                                            : base::SysUTF16ToNSString(
                                                  url_formatter::FormatUrl(url))];
}

void FiberWindow::LoadProgressChanged(double progress) {
  UpdateLoadProgress();
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
  NSString* spec = @"";
  NSString* display = @"";
  if (!url.is_empty()) {
    spec = base::SysUTF8ToNSString(url.spec());
    display = base::SysUTF16ToNSString(
        url_formatter::FormatUrlForDisplayOmitSchemePathAndTrivialSubdomains(
            url));
  }
  [controller_ updateWithURL:spec
               displayString:display
                       title:base::SysUTF16ToNSString(web_contents_->GetTitle())
                   canGoBack:controller.CanGoBack()
                canGoForward:controller.CanGoForward()
                   isLoading:web_contents_->IsLoading()];
}

void FiberWindow::UpdateLoadProgress() {
  [controller_ setLoading:web_contents_->ShouldShowLoadingUI()
                 progress:web_contents_->GetLoadProgress()];
}

void FiberWindow::Destroy() {
  delete this;
}

}  // namespace fiber
