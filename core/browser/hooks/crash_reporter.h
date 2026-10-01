#ifndef FIBER_BROWSER_HOOKS_CRASH_REPORTER_H_
#define FIBER_BROWSER_HOOKS_CRASH_REPORTER_H_

#include "base/functional/callback_forward.h"

namespace fiber {

// Runs `start`, which starts the browser's crash reporter (launching its
// handler process and waiting for it to answer), on another thread. Called by
// ChromeMainDelegate::PostEarlyInitialization().
void StartCrashReporter(base::OnceClosure start);

// Waits for StartCrashReporter()'s thread. Child processes inherit the
// handler's exception port as they launch, so ChromeBrowserMainPartsMac calls
// this before the browser's threads, which launch them, start.
void WaitForCrashReporter();

}  // namespace fiber

#endif  // FIBER_BROWSER_HOOKS_CRASH_REPORTER_H_
