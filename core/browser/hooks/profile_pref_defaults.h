#ifndef FIBER_BROWSER_HOOKS_PROFILE_PREF_DEFAULTS_H_
#define FIBER_BROWSER_HOOKS_PROFILE_PREF_DEFAULTS_H_

namespace user_prefs {
class PrefRegistrySyncable;
}

namespace fiber {

// Fiber's defaults for Chrome's profile prefs, which the user can still change
// in chrome://settings. Called at the end of RegisterProfilePrefs() (see
// patches/chromium/chrome-browser-prefs-browser_prefs.cc.patch).
void SetProfilePrefDefaults(user_prefs::PrefRegistrySyncable* registry);

// Registers Fiber's own profile prefs. Called from the same place.
void RegisterProfilePrefs(user_prefs::PrefRegistrySyncable* registry);

}  // namespace fiber

#endif  // FIBER_BROWSER_HOOKS_PROFILE_PREF_DEFAULTS_H_
