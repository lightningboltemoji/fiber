#include "fiber/browser/hooks/local_state_pref_defaults.h"

#include "base/values.h"
#include "chrome/common/pref_names.h"
#include "components/prefs/pref_registry_simple.h"

namespace fiber {

void SetLocalStatePrefDefaults(PrefRegistrySimple* registry) {
  // At startup, even with several profiles, the last used opens, rather than
  // the profile switcher (1: "disabled").
  registry->SetDefaultPrefValue(
      prefs::kBrowserProfilePickerAvailabilityOnStartup, base::Value(1));
  // Chrome's first run is in the Profile Picker too, so it counts as done.
  registry->SetDefaultPrefValue(prefs::kFirstRunFinished, base::Value(true));
}

}  // namespace fiber
