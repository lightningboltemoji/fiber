#ifndef FIBER_BROWSER_HOOKS_CONFIRM_QUIT_H_
#define FIBER_BROWSER_HOOKS_CONFIRM_QUIT_H_

#include <vector>

@class NSEvent;
@class NSString;
class Profile;

// Warn Before Quitting (holding Command-Q to quit), in Fiber's UI
// (FiberQuitConfirmation) in place of Chrome's ConfirmQuitPanelController.
// Called from AppController (see
// patches/chromium/chrome-browser-app_controller_mac.mm.patch), which checks
// the preference first.
namespace fiber {

// Runs as the user presses the quit shortcut, whose key-down is `event`, until
// they let go. Returns whether they confirmed the quit, in which case the
// browser windows are faded out.
bool ConfirmQuit(NSEvent* event);

// A confirmed quit didn't happen (a page kept its window open, say): brings
// the windows back.
void CancelConfirmQuit();

// The quit shortcut as menus show it, "⌘Q".
NSString* QuitKeyCommandString();

// Quitting found downloads in progress in `profiles`: lists them over the page
// in the window last used (or a new one), and quits once they're done or the
// user goes ahead without them. If the user stops waiting instead, the windows
// come back. In place of Chrome's alert asking whether to cancel them.
void WaitForDownloadsBeforeQuitting(const std::vector<Profile*>& profiles);

}  // namespace fiber

#endif  // FIBER_BROWSER_HOOKS_CONFIRM_QUIT_H_
