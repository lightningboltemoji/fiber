// Fiber's ProfilePicker: its profile switcher, over a browser window, in place
// of Chrome's views window, whose statics Fiber cuts (see
// patches/chromium/chrome-browser-ui-views-profiles-profile_picker_view.cc.patch).

#include "chrome/browser/ui/profiles/profile_picker.h"

#include <utility>

#include "base/files/file_path.h"
#include "base/functional/callback.h"
#include "chrome/browser/profiles/profile_manager.h"
#include "fiber/browser/profiles/profile_switcher.h"

using fiber::ProfileSwitcherPage;

// static
void ProfilePicker::Show(Params&& params) {
  switch (params.entry_point()) {
    case EntryPoint::kFirstRun:
      // Fiber counts its first run as done (local_state_pref_defaults.cc).
      params.NotifyFirstRunExited(FirstRunExitStatus::kCompleted,
                                  FirstRunFinishReason::kProfileAlreadySetUp);
      return;
    case EntryPoint::kGlicManager:
    case EntryPoint::kOmniboxEverywhere:
      params.NotifyProfilePicked(nullptr);
      return;
    case EntryPoint::kProfileMenuAddNewProfile:
    case EntryPoint::kAppMenuProfileSubMenuAddNewProfile:
    case EntryPoint::kOnStartupCreateProfileWithEmail:
      fiber::ShowProfileSwitcher(ProfileSwitcherPage::kNewProfile,
                                 /*may_open_window=*/true);
      return;
    case EntryPoint::kOnStartup:
    case EntryPoint::kProfileMenuManageProfiles:
    case EntryPoint::kAppMenuProfileSubMenuManageProfiles:
    case EntryPoint::kOpenNewWindowAfterProfileDeletion:
    case EntryPoint::kNewSessionOnExistingProcess:
    case EntryPoint::kBackgroundModeManager:
      fiber::ShowProfileSwitcher(ProfileSwitcherPage::kProfiles,
                                 /*may_open_window=*/true);
      return;
    // The profile wanted can't open, or none can. A window opened for another
    // could land here again.
    case EntryPoint::kProfileLocked:
    case EntryPoint::kUnableToCreateBrowser:
    case EntryPoint::kProfileIdle:
    case EntryPoint::kOnStartupNoProfile:
    case EntryPoint::kNewSessionOnExistingProcessNoProfile:
      fiber::ShowProfileSwitcher(ProfileSwitcherPage::kProfiles,
                                 /*may_open_window=*/false);
      return;
  }
}

// Signing in, and the rest of the picker's own flows, which Fiber doesn't
// have.

// static
void ProfilePicker::SwitchToSignIn(
    ProfileInfo profile_info,
    base::OnceCallback<void(bool)> switch_finished_callback) {
  std::move(switch_finished_callback).Run(false);
}

// static
void ProfilePicker::SwitchToReauth(
    Profile* profile,
    base::OnceCallback<void(bool)> switch_finished_callback,
    base::OnceCallback<void(const ForceSigninUIError&)> on_error_callback) {
  std::move(switch_finished_callback).Run(false);
}

// static
void ProfilePicker::SwitchToSignedOutPostIdentityFlow(
    std::optional<SkColor> profile_color) {}

// static
void ProfilePicker::PickProfile(
    const base::FilePath& profile_path,
    ProfilePickingArgs args,
    base::OnceCallback<void(bool)> pick_profile_complete_callback) {
  std::move(pick_profile_complete_callback).Run(false);
}

// static
void ProfilePicker::CancelSignInFlow() {}

// static
base::FilePath ProfilePicker::GetPickerProfilePath() {
  return ProfileManager::GetSystemProfilePath();
}

// static
void ProfilePicker::Hide() {
  fiber::CloseProfileSwitcher();
}

// The switcher is over a browser window, which is what callers look for when
// the picker isn't open.

// static
bool ProfilePicker::IsOpen() {
  return false;
}

// static
bool ProfilePicker::IsFirstRunOpen() {
  return false;
}

// static
bool ProfilePicker::IsActive() {
  return false;
}

// static
views::View* ProfilePicker::GetViewForTesting() {
  return nullptr;
}

// static
views::WebView* ProfilePicker::GetWebViewForTesting() {
  return nullptr;
}

// static
void ProfilePicker::AddOnProfilePickerOpenedCallbackForTesting(
    base::OnceClosure callback) {}
