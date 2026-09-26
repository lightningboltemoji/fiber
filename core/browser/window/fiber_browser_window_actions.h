#ifndef FIBER_BROWSER_WINDOW_FIBER_BROWSER_WINDOW_ACTIONS_H_
#define FIBER_BROWSER_WINDOW_FIBER_BROWSER_WINDOW_ACTIONS_H_

#import <Cocoa/Cocoa.h>

#import "FiberBridge/FiberWindow.h"

namespace fiber {
class FiberBrowserWindow;
}

// Carries out what the user does in a Fiber window's UI on its
// FiberBrowserWindow.
//
// Also handles the commands Chrome's main menu sends (-commandDispatch: and
// -commandDispatchUsingKeyModifiers:, with the command ID as the sender's
// tag). The window forwards them here while it's key, ahead of Chrome's
// AppController, so menu items act on this window's browser.
@interface FiberBrowserWindowActions
    : NSObject <FiberWindowActions, NSUserInterfaceValidations>

- (instancetype)initWithOwner:(fiber::FiberBrowserWindow*)owner;

// Called by the owner when it is being destroyed. Later calls do nothing.
- (void)detachOwner;

@end

#endif  // FIBER_BROWSER_WINDOW_FIBER_BROWSER_WINDOW_ACTIONS_H_
