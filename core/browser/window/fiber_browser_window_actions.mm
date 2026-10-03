#import "fiber/browser/window/fiber_browser_window_actions.h"

#include <algorithm>

#include "base/apple/foundation_util.h"
#include "base/memory/raw_ptr.h"
#include "base/notreached.h"
#include "base/strings/sys_string_conversions.h"
#include "chrome/app/chrome_command_ids.h"
#include "fiber/browser/pins/pinned_tabs.h"
#include "fiber/browser/window/fiber_browser_window.h"
#import "ui/base/cocoa/cocoa_base_utils.h"
#include "ui/base/window_open_disposition.h"

namespace {

// Where to open a page, from the modifier keys of the event that asked for it.
WindowOpenDisposition DispositionFromEvent(NSEvent* event) {
  return event ? ui::WindowOpenDispositionFromNSEvent(event)
               : WindowOpenDisposition::CURRENT_TAB;
}

int CommandID(FiberCommand command) {
  switch (command) {
    case FiberCommandNewTab:
      return IDC_NEW_TAB;
    case FiberCommandPrint:
      return IDC_PRINT;
  }
  NOTREACHED();
}

}  // namespace

@implementation FiberBrowserWindowActions {
  raw_ptr<fiber::FiberBrowserWindow> _owner;
}

- (instancetype)initWithOwner:(fiber::FiberBrowserWindow*)owner {
  if ((self = [super init])) {
    _owner = owner;
  }
  return self;
}

- (void)detachOwner {
  _owner = nullptr;
}

- (fiber::PinnedTabs*)pinnedTabs {
  return _owner ? _owner->pinned_tabs() : nullptr;
}

- (void)executeCommand:(int)command
           disposition:(WindowOpenDisposition)disposition {
  if (_owner) {
    _owner->ExecuteCommand(command, disposition);
  }
}

// FiberWindowActions:

- (void)goBackWithEvent:(NSEvent*)event {
  [self executeCommand:IDC_BACK disposition:DispositionFromEvent(event)];
}

- (void)goForwardWithEvent:(NSEvent*)event {
  [self executeCommand:IDC_FORWARD disposition:DispositionFromEvent(event)];
}

- (void)reloadWithEvent:(NSEvent*)event {
  [self executeCommand:IDC_RELOAD disposition:DispositionFromEvent(event)];
}

- (void)stopLoading {
  [self executeCommand:IDC_STOP disposition:WindowOpenDisposition::CURRENT_TAB];
}

- (void)focusPage {
  if (_owner) {
    _owner->FocusWebContents();
  }
}

- (void)restoreFocus {
  if (_owner) {
    _owner->RestoreFocus();
  }
}

- (void)pressSadTabButton {
  if (_owner) {
    _owner->PerformSadTabAction(SadTab::Action::kButton);
  }
}

- (void)openSadTabHelp {
  if (_owner) {
    _owner->PerformSadTabAction(SadTab::Action::kHelpLink);
  }
}

- (void)selectTabWithID:(NSInteger)tabID {
  if (_owner) {
    _owner->SelectTab(static_cast<int32_t>(tabID));
  }
}

- (void)revealText:(NSString*)text inTabWithID:(NSInteger)tabID {
  if (_owner) {
    _owner->RevealText(static_cast<int32_t>(tabID),
                       base::SysNSStringToUTF16(text));
  }
}

- (void)closeTabWithID:(NSInteger)tabID {
  if (_owner) {
    _owner->CloseTab(static_cast<int32_t>(tabID));
  }
}

- (void)pinTabWithID:(NSInteger)tabID {
  if (fiber::PinnedTabs* pinned_tabs = [self pinnedTabs]) {
    pinned_tabs->PinTab(static_cast<int32_t>(tabID));
  }
}

- (void)openPinWithID:(NSString*)pinID {
  if (fiber::PinnedTabs* pinned_tabs = [self pinnedTabs]) {
    pinned_tabs->Open(base::SysNSStringToUTF8(pinID));
  }
}

- (void)resetPinWithID:(NSString*)pinID {
  if (fiber::PinnedTabs* pinned_tabs = [self pinnedTabs]) {
    pinned_tabs->Reset(base::SysNSStringToUTF8(pinID));
  }
}

- (void)updateURLOfPinWithID:(NSString*)pinID {
  if (fiber::PinnedTabs* pinned_tabs = [self pinnedTabs]) {
    pinned_tabs->UpdateURL(base::SysNSStringToUTF8(pinID));
  }
}

- (void)unpinPinWithID:(NSString*)pinID {
  if (fiber::PinnedTabs* pinned_tabs = [self pinnedTabs]) {
    pinned_tabs->Unpin(base::SysNSStringToUTF8(pinID));
  }
}

- (void)movePinWithID:(NSString*)pinID toIndex:(NSInteger)index {
  if (fiber::PinnedTabs* pinned_tabs = [self pinnedTabs]) {
    pinned_tabs->Move(base::SysNSStringToUTF8(pinID),
                      static_cast<size_t>(std::max<NSInteger>(index, 0)));
  }
}

- (BOOL)canRunCommand:(FiberCommand)command {
  return _owner && _owner->IsCommandEnabled(CommandID(command));
}

- (void)runCommand:(FiberCommand)command {
  [self executeCommand:CommandID(command)
           disposition:WindowOpenDisposition::CURRENT_TAB];
}

- (void)commandPaletteDidOpen {
  if (_owner) {
    _owner->OnCommandPaletteOpened();
  }
}

- (void)capturePageThumbnail:(void (^)(CGImageRef thumbnail))completion {
  if (_owner) {
    _owner->CapturePageThumbnail(completion);
  } else {
    completion(nullptr);
  }
}

- (void)windowShouldClose {
  if (_owner) {
    _owner->OnWindowCloseRequested();
  }
}

- (void)windowDidBecomeMain {
  if (_owner) {
    _owner->OnWindowActivationChanged(true);
  }
}

- (void)windowDidResignMain {
  if (_owner) {
    _owner->OnWindowActivationChanged(false);
  }
}

- (void)windowDidChangeFullScreen {
  if (_owner) {
    _owner->OnWindowFullscreenChanged();
  }
}

// Chrome's main menu commands:

- (void)commandDispatch:(id)sender {
  [self executeCommand:[sender tag]
           disposition:WindowOpenDisposition::CURRENT_TAB];
}

// For items that open their page where the modifier keys say, like History
// items.
- (void)commandDispatchUsingKeyModifiers:(id)sender {
  [self executeCommand:[sender tag]
           disposition:DispositionFromEvent(NSApp.currentEvent)];
}

- (BOOL)validateUserInterfaceItem:(id<NSValidatedUserInterfaceItem>)item {
  if (item.action != @selector(commandDispatch:) &&
      item.action != @selector(commandDispatchUsingKeyModifiers:)) {
    return YES;
  }
  if (!_owner) {
    return NO;
  }
  // Pin Tab has a checkmark on a pinned tab, as in Chrome.
  NSMenuItem* menu_item = base::apple::ObjCCast<NSMenuItem>(item);
  if (menu_item && item.tag == IDC_WINDOW_PIN_TAB) {
    menu_item.state = _owner->IsActiveTabPinned() ? NSControlStateValueOn
                                                  : NSControlStateValueOff;
  }
  return _owner->IsCommandEnabled(item.tag);
}

@end
