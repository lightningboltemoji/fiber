#include "fiber/browser/extensions/fiber_extension_popup.h"

#import <AppKit/AppKit.h>

#include <utility>

#import "FiberBridge/FiberExtensions.h"
#include "base/check_op.h"
#include "base/functional/bind.h"
#include "base/memory/raw_ptr.h"
#include "base/strings/sys_string_conversions.h"
#include "base/task/sequenced_task_runner.h"
#include "chrome/browser/devtools/devtools_toggle_action.h"
#include "chrome/browser/devtools/devtools_window.h"
#include "chrome/browser/extensions/extension_view_host.h"
#include "content/public/browser/render_frame_host.h"
#include "content/public/browser/render_widget_host_view.h"
#include "content/public/browser/web_contents.h"

// Forwards the popup's closing to its FiberExtensionPopup.
@interface FiberExtensionPopupActionsBridge
    : NSObject <FiberExtensionPopupActions>
- (instancetype)initWithOwner:(fiber::FiberExtensionPopup*)owner;
- (void)detachOwner;
@end

@implementation FiberExtensionPopupActionsBridge {
  raw_ptr<fiber::FiberExtensionPopup> _owner;
}

- (instancetype)initWithOwner:(fiber::FiberExtensionPopup*)owner {
  if ((self = [super init])) {
    _owner = owner;
  }
  return self;
}

- (void)detachOwner {
  _owner = nullptr;
}

- (void)extensionPopupDidClose {
  if (_owner) {
    _owner->OnClosedByUser();
  }
}

@end

namespace fiber {

FiberExtensionPopup::FiberExtensionPopup(
    std::unique_ptr<extensions::ExtensionViewHost> host,
    id<FiberExtensions> ui,
    const std::string& action_id,
    PopupShowAction show_action,
    ShowPopupCallback shown_callback,
    base::OnceClosure closed)
    : host_(std::move(host)),
      inspect_(show_action == PopupShowAction::kShowAndInspect),
      shown_callback_(std::move(shown_callback)),
      closed_(std::move(closed)),
      actions_([[FiberExtensionPopupActionsBridge alloc] initWithOwner:this]) {
  // The host calls its view from here on, so it's set first.
  host_->set_view(this);
  // Safe: this owns the host, so the handler can't outlive it.
  host_->SetCloseHandler(base::BindOnce(&FiberExtensionPopup::OnHostClosed,
                                        base::Unretained(this)));
  WebContentsObserver::Observe(host_->host_contents());
  ui_ = [ui popupForExtensionWithID:base::SysUTF8ToNSString(action_id)
                       contentsView:GetContentsView()
                            actions:actions_];
  const gfx::Size min_size = extensions::kExtensionPopupMinSize;
  [ui_ setContentSize:NSMakeSize(min_size.width(), min_size.height())];
  content::RenderFrameHost* main_frame =
      host_->host_contents()->GetPrimaryMainFrame();
  if (main_frame->IsRenderFrameLive()) {
    SetUpMainFrame(main_frame);
  }
  host_->CreateRendererSoon();
}

FiberExtensionPopup::~FiberExtensionPopup() {
  [actions_ detachOwner];
  [ui_ close];
  if (shown_callback_) {
    // It never showed.
    std::move(shown_callback_).Run(nullptr);
  }
}

NSView* FiberExtensionPopup::GetContentsView() const {
  return host_->host_contents()->GetNativeView().GetNativeNSView();
}

void FiberExtensionPopup::OnClosedByUser() {
  [actions_ detachOwner];
  if (!closed_) {
    return;
  }
  // Not from within the host, or AppKit's closing of the popover.
  base::SequencedTaskRunner::GetCurrentDefault()->PostTask(
      FROM_HERE, std::move(closed_));
}

gfx::NativeView FiberExtensionPopup::GetNativeView() {
  return host_->host_contents()->GetNativeView();
}

void FiberExtensionPopup::ResizeDueToAutoResize(
    content::WebContents* web_contents,
    const gfx::Size& new_size) {
  [ui_ setContentSize:NSMakeSize(new_size.width(), new_size.height())];
}

void FiberExtensionPopup::RenderFrameCreated(
    content::RenderFrameHost* render_frame_host) {
  // Only the main frame, not a speculative one (see RenderFrameHostChanged()).
  if (render_frame_host == host_->host_contents()->GetPrimaryMainFrame()) {
    SetUpMainFrame(render_frame_host);
  }
}

bool FiberExtensionPopup::HandleKeyboardEvent(
    content::WebContents* source,
    const input::NativeWebKeyboardEvent& event) {
  // The host has already closed the popup on Escape. The rest go to the page.
  return false;
}

void FiberExtensionPopup::OnLoaded() {
  [ui_ show];
  host_->host_contents()->Focus();
  if (shown_callback_) {
    std::move(shown_callback_).Run(host_.get());
  }
  if (inspect_) {
    DevToolsWindow::OpenDevToolsWindow(
        host_->host_contents(), DevToolsToggleAction::ShowConsolePanel(),
        DevToolsOpenedByAction::kContextMenuInspect);
  }
}

void FiberExtensionPopup::RenderFrameHostChanged(
    content::RenderFrameHost* old_host,
    content::RenderFrameHost* new_host) {
  // A main frame swapped in; the initial one has no renderer frame yet.
  if (old_host && new_host == host_->host_contents()->GetPrimaryMainFrame()) {
    SetUpMainFrame(new_host);
  }
}

void FiberExtensionPopup::SetUpMainFrame(
    content::RenderFrameHost* render_frame_host) {
  render_frame_host->GetView()->EnableAutoResize(
      extensions::kExtensionPopupMinSize, extensions::kExtensionPopupMaxSize);
}

void FiberExtensionPopup::OnHostClosed(extensions::ExtensionHost* host) {
  DCHECK_EQ(host, host_.get());
  OnClosedByUser();
}

}  // namespace fiber
