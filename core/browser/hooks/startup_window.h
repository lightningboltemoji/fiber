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
// window where the last startup's went, with nothing on its page yet. The
// first normal, non-Incognito browser takes it over (TakeStartupWindow()), and
// its page shows once AppKit has finished launching; if no browser has taken
// it by then (Incognito by policy, say), it closes.
//
// Called by ChromeMainDelegate::PostEarlyInitialization(), once the process
// singleton is held.
void ShowStartupWindow();

#if defined(__OBJC__)
// The startup window, for the first normal browser; nil if there isn't one
// (any more).
id<FiberWindow> TakeStartupWindow();
#endif

}  // namespace fiber

#endif  // FIBER_BROWSER_HOOKS_STARTUP_WINDOW_H_
