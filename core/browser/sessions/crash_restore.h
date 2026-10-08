#ifndef FIBER_BROWSER_SESSIONS_CRASH_RESTORE_H_
#define FIBER_BROWSER_SESSIONS_CRASH_RESTORE_H_

namespace user_prefs {
class PrefRegistrySyncable;
}

namespace fiber {

// Restoring after a crash (see hooks/crash_restore.h) remembers it's under
// way in the profile's prefs, for a minute, so that if it crashes too the
// next launch asks instead.
void RegisterCrashRestorePrefs(user_prefs::PrefRegistrySyncable* registry);

}  // namespace fiber

#endif  // FIBER_BROWSER_SESSIONS_CRASH_RESTORE_H_
