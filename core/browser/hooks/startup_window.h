#ifndef FIBER_BROWSER_HOOKS_STARTUP_WINDOW_H_
#define FIBER_BROWSER_HOOKS_STARTUP_WINDOW_H_

// Included from C++ (the patch) and Objective-C++ (FiberBrowserWindow).
#if defined(__OBJC__)
#import <Foundation/Foundation.h>

@protocol FiberWindow;
#endif

namespace fiber {

// Shows the first browser window as soon as this process knows it's the
// browser, before Chrome has loaded the profile and made the browser: a Fiber
// window guessed from how the last startup went (where the window was, and
// whether it opened on the New Tab page). The first normal, non-Incognito
// browser takes it over (TakeStartupWindow()); if none has by the time the
// main loop runs (Incognito by policy, say), it closes.
//
// Called by ChromeMainDelegate::PostEarlyInitialization(), once the process
// singleton is held.
void ShowStartupWindow();

#if defined(__OBJC__)
// The startup window, for the first normal browser; nil if there isn't one
// (any more).
id<FiberWindow> TakeStartupWindow();

// Records how the browser that took over the startup window first showed it,
// for the next startup window to show the same.
void RecordStartupWindow(NSRect frame, bool new_tab_page);
#endif

}  // namespace fiber

#endif  // FIBER_BROWSER_HOOKS_STARTUP_WINDOW_H_
