#ifndef FIBER_BROWSER_HOOKS_FRAMEWORK_PREFETCH_H_
#define FIBER_BROWSER_HOOKS_FRAMEWORK_PREFETCH_H_

namespace fiber {

// In the browser process, reads the framework's code and data ahead of use on
// a background thread, so a cold start (after a restart, say, when none of it
// is in memory) reads it from disk at full speed rather than a page at a time
// as startup gets to it: Chrome's startup runs code from all over the
// framework, and its other processes use the same file. Does next to nothing
// when it's already in memory.
//
// Called by ChromeMain(), first thing.
void PrefetchFramework(int argc, const char** argv);

}  // namespace fiber

#endif  // FIBER_BROWSER_HOOKS_FRAMEWORK_PREFETCH_H_
