#ifndef FIBER_BROWSER_HOOKS_LOCAL_STATE_PREF_DEFAULTS_H_
#define FIBER_BROWSER_HOOKS_LOCAL_STATE_PREF_DEFAULTS_H_

class PrefRegistrySimple;

namespace fiber {

// Fiber's defaults for Chrome's local state prefs, the ones for the whole app
// rather than a profile. Called at the end of RegisterLocalState() (see
// patches/chromium/chrome-browser-prefs-browser_prefs.cc.patch).
void SetLocalStatePrefDefaults(PrefRegistrySimple* registry);

}  // namespace fiber

#endif  // FIBER_BROWSER_HOOKS_LOCAL_STATE_PREF_DEFAULTS_H_
