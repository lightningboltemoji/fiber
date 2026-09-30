#ifndef FIBER_BROWSER_PROFILES_PROFILE_SWITCHER_H_
#define FIBER_BROWSER_PROFILES_PROFILE_SWITCHER_H_

class BrowserWindowInterface;

namespace fiber {

enum class ProfileSwitcherPage {
  kProfiles,
  kNewProfile,
};

// Fiber's profile switcher (FiberProfileSwitcherFactory), over `browser`'s
// window, in place of any other. Chrome's Profile Picker opens it too (see
// profile_picker.cc).
void ShowProfileSwitcher(BrowserWindowInterface* browser,
                         ProfileSwitcherPage page);

// Over the window last used. With none, if `may_open_window`, over a new
// window of the profile last used, unless it's locked.
void ShowProfileSwitcher(ProfileSwitcherPage page, bool may_open_window);

void CloseProfileSwitcher();

}  // namespace fiber

#endif  // FIBER_BROWSER_PROFILES_PROFILE_SWITCHER_H_
