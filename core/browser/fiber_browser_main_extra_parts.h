#ifndef FIBER_BROWSER_FIBER_BROWSER_MAIN_EXTRA_PARTS_H_
#define FIBER_BROWSER_FIBER_BROWSER_MAIN_EXTRA_PARTS_H_

#include "base/memory/raw_ptr.h"
#include "chrome/browser/chrome_browser_main_extra_parts.h"

class Profile;

namespace fiber {

// Fiber's hook into Chrome's browser startup and shutdown sequence. Opens the
// first Fiber window once the initial profile is ready, and tears windows down
// before Chrome destroys profiles.
class FiberBrowserMainExtraParts : public ChromeBrowserMainExtraParts {
 public:
  FiberBrowserMainExtraParts();
  FiberBrowserMainExtraParts(const FiberBrowserMainExtraParts&) = delete;
  FiberBrowserMainExtraParts& operator=(const FiberBrowserMainExtraParts&) =
      delete;
  ~FiberBrowserMainExtraParts() override;

  // ChromeBrowserMainExtraParts:
  void PostProfileInit(Profile* profile, bool is_initial_profile) override;
  void PostBrowserStart() override;
  void PostMainMessageLoopRun() override;

 private:
  // Only valid between PostProfileInit() and PostBrowserStart().
  raw_ptr<Profile> initial_profile_ = nullptr;
};

}  // namespace fiber

#endif  // FIBER_BROWSER_FIBER_BROWSER_MAIN_EXTRA_PARTS_H_
