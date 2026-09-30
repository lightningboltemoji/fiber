#include "fiber/browser/hooks/local_state_pref_defaults.h"

#include "base/values.h"
#include "chrome/common/pref_names.h"
#include "components/prefs/pref_registry_simple.h"

namespace fiber {

void SetLocalStatePrefDefaults(PrefRegistrySimple* registry) {
  // Chrome's Profile Picker is a views window. Until Fiber has its own way,
  // Profiles › Add Profile… doesn't show, and at startup, even with several
  // profiles, the last used opens instead (1: "disabled").
  registry->SetDefaultPrefValue(prefs::kBrowserAddPersonEnabled,
                                base::Value(false));
  registry->SetDefaultPrefValue(
      prefs::kBrowserProfilePickerAvailabilityOnStartup, base::Value(1));
  // Chrome's first run is in the Profile Picker too, so it counts as done.
  registry->SetDefaultPrefValue(prefs::kFirstRunFinished, base::Value(true));
}

}  // namespace fiber
