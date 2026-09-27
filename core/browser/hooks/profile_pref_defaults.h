#ifndef FIBER_BROWSER_HOOKS_PROFILE_PREF_DEFAULTS_H_
#define FIBER_BROWSER_HOOKS_PROFILE_PREF_DEFAULTS_H_

namespace user_prefs {
class PrefRegistrySyncable;
}

namespace fiber {

// Changes the defaults of profile prefs Chrome registered, where Fiber's
// differ. The user can still change them in chrome://settings. Called at the
// end of RegisterProfilePrefs() (see patches/chromium/
// chrome-browser-prefs-browser_prefs.cc.patch).
void SetProfilePrefDefaults(user_prefs::PrefRegistrySyncable* registry);

}  // namespace fiber

#endif  // FIBER_BROWSER_HOOKS_PROFILE_PREF_DEFAULTS_H_
