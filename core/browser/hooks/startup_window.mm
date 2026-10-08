#include "fiber/browser/hooks/startup_window.h"

#import <Cocoa/Cocoa.h>
#import <QuartzCore/QuartzCore.h>

#include <algorithm>

#import "FiberBridge/FiberBridge.h"
#include "base/command_line.h"
#include "base/functional/bind.h"
#include "base/location.h"
#include "base/task/single_thread_task_runner.h"
#include "chrome/common/chrome_switches.h"
#include "components/embedder_support/switches.h"
#include "content/public/common/content_switches.h"

namespace fiber {

namespace {

// Where the last normal window went, in the app's user defaults.
NSString* const kFrameKey = @"FiberStartupWindowFrame";

// Chrome's window sizer puts a new window without a saved placement this far
// in from the primary screen's visible frame, at most this wide (see
// window_sizer_mac.mm).
constexpr CGFloat kDefaultInset = 22;
constexpr CGFloat kDefaultMaxWidth = 1200;

// Until AppKit has finished launching, and whether a browser has taken it over
// by then.
id<FiberWindow> g_startup_window;
bool g_taken = false;

// Whether Chrome is starting the way it usually does: with a browser window
// of its own, which Fiber draws.
bool ShouldShow(const base::CommandLine& command_line) {
  const char* const kSwitches[] = {
      // No window: background mode, or another process's request.
      switches::kNoStartupWindow,
      switches::kSilentLaunch,
      // App windows, which aren't Fiber's.
      switches::kApp,
      switches::kAppId,
      // An Incognito window, which the startup window isn't.
      switches::kIncognito,
      // Tests and automation.
      switches::kTestType,
      embedder_support::kHeadless,
  };
  return std::ranges::none_of(kSwitches, [&](const char* name) {
    return command_line.HasSwitch(name);
  });
}

// Where the window went last time, if that's still on a screen; otherwise
// where Chrome puts a window the first time.
NSRect StartupFrame() {
  NSString* saved =
      [NSUserDefaults.standardUserDefaults stringForKey:kFrameKey];
  NSRect frame = saved ? NSRectFromString(saved) : NSZeroRect;
  if (!NSIsEmptyRect(frame)) {
    for (NSScreen* screen in NSScreen.screens) {
      if (NSIntersectsRect(screen.visibleFrame, frame)) {
        return frame;
      }
    }
  }
  NSScreen* primary = NSScreen.screens.firstObject;
  if (!primary) {
    return NSZeroRect;
  }
  NSRect area = primary.visibleFrame;
  return NSMakeRect(
      NSMinX(area) + kDefaultInset, NSMinY(area) + kDefaultInset,
      std::min(NSWidth(area) - 2 * kDefaultInset, kDefaultMaxWidth),
      NSHeight(area) - 2 * kDefaultInset);
}

void FinishStartupWindow() {
  id<FiberWindow> window = g_startup_window;
  g_startup_window = nil;
  if (!window) {
    return;
  }
  if (g_taken) {
    [window showPage];
    RememberStartupWindowFrame(window.window.frame);
  } else {
    [window.window close];
  }
}

}  // namespace

void ShowStartupWindow() {
  if (!ShouldShow(*base::CommandLine::ForCurrentProcess())) {
    return;
  }
  g_startup_window = [FiberWindowFactory startupWindowWithFrame:StartupFrame()];
  NSWindow* window = g_startup_window.window;
  [window makeKeyAndOrderFront:nil];
  // Drawn and on screen now: the main loop, which would otherwise do it,
  // doesn't run until the browser has started.
  [window displayIfNeeded];
  [CATransaction flush];

  // Links from other apps are Apple events, which arrive as AppKit finishes
  // launching; AppController opens them in place of the New Tab page when it's
  // told it has, after this observer.
  __block id<NSObject> observer = [NSNotificationCenter.defaultCenter
      addObserverForName:NSApplicationDidFinishLaunchingNotification
                  object:nil
                   queue:nil
              usingBlock:^(NSNotification*) {
                [NSNotificationCenter.defaultCenter removeObserver:observer];
                observer = nil;
                base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(
                    FROM_HERE, base::BindOnce(&FinishStartupWindow));
              }];
}

void RememberStartupWindowFrame(NSRect frame) {
  [NSUserDefaults.standardUserDefaults setObject:NSStringFromRect(frame)
                                          forKey:kFrameKey];
}

id<FiberWindow> TakeStartupWindow() {
  if (g_taken) {
    return nil;
  }
  g_taken = true;
  return g_startup_window;
}

}  // namespace fiber
