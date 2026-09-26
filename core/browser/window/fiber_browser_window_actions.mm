#import "fiber/browser/window/fiber_browser_window_actions.h"

#include "base/memory/raw_ptr.h"
#include "base/strings/sys_string_conversions.h"
#include "chrome/app/chrome_command_ids.h"
#include "fiber/browser/window/fiber_browser_window.h"
#import "ui/base/cocoa/cocoa_base_utils.h"
#include "ui/base/window_open_disposition.h"

namespace {

// Where to open a page, from the modifier keys of the event that asked for it.
WindowOpenDisposition DispositionFromEvent(NSEvent* event) {
  return event ? ui::WindowOpenDispositionFromNSEvent(event)
               : WindowOpenDisposition::CURRENT_TAB;
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

- (void)navigateToInput:(NSString*)input event:(NSEvent*)event {
  if (_owner) {
    _owner->NavigateToInput(base::SysNSStringToUTF16(input),
                            DispositionFromEvent(event));
  }
}

- (void)focusPage {
  if (_owner) {
    _owner->FocusWebContents();
  }
}

- (void)selectTabWithID:(NSInteger)tabID {
  if (_owner) {
    _owner->SelectTab(static_cast<int32_t>(tabID));
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
  return _owner && _owner->IsCommandEnabled(item.tag);
}

@end
