#ifndef FIBER_BROWSER_HOOKS_CONFIRM_QUIT_H_
#define FIBER_BROWSER_HOOKS_CONFIRM_QUIT_H_

#include <vector>

@class NSEvent;
@class NSString;
class Profile;

// Warn Before Quitting (holding Command-Q to quit), in place of Chrome's
// ConfirmQuitPanelController. Called from AppController, which checks the
// pref first (see patches/chromium/chrome-browser-app_controller_mac.mm.patch).
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
// in the last active window (or a new one), in place of Chrome's alert. Quits
// once they're done or the user goes ahead; cancelling brings the windows back.
void WaitForDownloadsBeforeQuitting(const std::vector<Profile*>& profiles);

}  // namespace fiber

#endif  // FIBER_BROWSER_HOOKS_CONFIRM_QUIT_H_
