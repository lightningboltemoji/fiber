#ifndef FIBER_BROWSER_HOOKS_CRASH_RESTORE_H_
#define FIBER_BROWSER_HOOKS_CRASH_RESTORE_H_

class BrowserWindowInterface;
class Profile;

namespace fiber {

// Whether Fiber restores the profile's windows after its last session crashed,
// as it does after a quit: if it restores on startup, and unless restoring
// after a crash just crashed too. Decided once per launch, as it starts. Called
// by HasPendingUncleanExit(), which is then false.
bool RestoresAfterCrash(Profile* profile);

// In place of Chrome's crash bubble (AddInfoBarsIfNecessary()), when Fiber
// didn't restore after a crash: offers to, over `browser`'s page.
void OfferRestoreAfterCrash(BrowserWindowInterface* browser);

}  // namespace fiber

#endif  // FIBER_BROWSER_HOOKS_CRASH_RESTORE_H_
