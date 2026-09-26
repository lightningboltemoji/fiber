#include "fiber/browser/fiber_browser_main_extra_parts.h"

#include "base/command_line.h"
#include "fiber/browser/fiber_window.h"
#include "url/gurl.h"

namespace fiber {

namespace {

constexpr char kDefaultStartURL[] = "https://www.google.com/";

// The first non-switch argument, if any, overrides the start page.
GURL GetStartURL() {
  const auto args = base::CommandLine::ForCurrentProcess()->GetArgs();
  if (!args.empty()) {
    GURL url(args.front());
    if (url.is_valid()) {
      return url;
    }
  }
  return GURL(kDefaultStartURL);
}

}  // namespace

FiberBrowserMainExtraParts::FiberBrowserMainExtraParts() = default;
FiberBrowserMainExtraParts::~FiberBrowserMainExtraParts() = default;

void FiberBrowserMainExtraParts::PostProfileInit(Profile* profile,
                                                 bool is_initial_profile) {
  if (is_initial_profile) {
    initial_profile_ = profile;
  }
}

void FiberBrowserMainExtraParts::PostBrowserStart() {
  if (initial_profile_) {
    FiberWindow::Create(initial_profile_, GetStartURL());
  }
  initial_profile_ = nullptr;
}

void FiberBrowserMainExtraParts::PostMainMessageLoopRun() {
  FiberWindow::CloseAll();
}

}  // namespace fiber
