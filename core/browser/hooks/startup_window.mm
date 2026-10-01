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

// How the last startup went, in the app's user defaults.
NSString* const kFrameKey = @"FiberStartupWindowFrame";
NSString* const kNewTabPageKey = @"FiberStartupWindowNewTabPage";

// Chrome's window sizer puts a new window without a saved placement this far
// in from the primary screen's visible frame, at most this wide (see
// window_sizer_mac.mm).
constexpr CGFloat kDefaultInset = 22;
constexpr CGFloat kDefaultMaxWidth = 1200;

id<FiberWindow> g_startup_window;
// Pages to open on the command line, which the browser opens in place of the
// New Tab page.
bool g_has_urls = false;

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

void CloseUnclaimedStartupWindow() {
  if (id<FiberWindow> window = TakeStartupWindow()) {
    [window.window close];
  }
}

}  // namespace

void ShowStartupWindow() {
  const base::CommandLine& command_line =
      *base::CommandLine::ForCurrentProcess();
  if (!ShouldShow(command_line)) {
    return;
  }
  NSUserDefaults* defaults = NSUserDefaults.standardUserDefaults;
  // A browser starts on the New Tab page, unless the last one didn't (it
  // restored the last session, say), or there are pages to open.
  g_has_urls = !command_line.GetArgs().empty();
  bool new_tab_page = !g_has_urls &&
                      ([defaults objectForKey:kNewTabPageKey] == nil ||
                       [defaults boolForKey:kNewTabPageKey]);
  g_startup_window =
      [FiberWindowFactory startupWindowWithFrame:StartupFrame()
                                      newTabPage:new_tab_page];
  NSWindow* window = g_startup_window.window;
  [window makeKeyAndOrderFront:nil];
  // Drawn and on screen now: the main loop, which would otherwise do it,
  // doesn't run until the browser has started.
  [window displayIfNeeded];
  [CATransaction flush];

  // This runs once the main loop does, after Chrome's usual startup has made
  // its first browser.
  base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(
      FROM_HERE, base::BindOnce(&CloseUnclaimedStartupWindow));
}

id<FiberWindow> TakeStartupWindow() {
  id<FiberWindow> window = g_startup_window;
  g_startup_window = nil;
  return window;
}

void RecordStartupWindow(NSRect frame, bool new_tab_page) {
  NSUserDefaults* defaults = NSUserDefaults.standardUserDefaults;
  [defaults setObject:NSStringFromRect(frame) forKey:kFrameKey];
  // Pages from the command line say nothing about how the next startup goes.
  if (!g_has_urls) {
    [defaults setBool:new_tab_page forKey:kNewTabPageKey];
  }
}

}  // namespace fiber
