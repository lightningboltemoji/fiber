#include "fiber/browser/hooks/profile_pref_defaults.h"

#include "base/values.h"
#include "chrome/common/pref_names.h"
#include "components/pref_registry/pref_registry_syncable.h"
#include "fiber/browser/pins/pin_store.h"

namespace fiber {

void SetProfilePrefDefaults(user_prefs::PrefRegistrySyncable* registry) {
  // "Autocomplete searches and URLs": off, so the omnibox doesn't send what's
  // typed to the search engine for suggestions. Its suggestions come from the
  // user's own history, bookmarks, and tabs.
  registry->SetDefaultPrefValue(prefs::kSearchSuggestEnabled,
                                base::Value(false));
  // Printing goes straight to the system's print panel, not Chrome's print
  // preview.
  registry->SetDefaultPrefValue(prefs::kPrintPreviewDisabled,
                                base::Value(true));
  // Chrome's sharing hub (a QR code, sending to devices), a views bubble:
  // off, and with it the command palette's "Share this page". Sharing goes
  // through the Share menu.
  registry->SetDefaultPrefValue(prefs::kDesktopSharingHubEnabled,
                                base::Value(false));
  // "Ask where to save each file before downloading": on, so a download
  // goes where the user picks rather than straight to the Downloads folder.
  registry->SetDefaultPrefValue(prefs::kPromptForDownload, base::Value(true));
}

void RegisterProfilePrefs(user_prefs::PrefRegistrySyncable* registry) {
  PinStore::RegisterProfilePrefs(registry);
}

}  // namespace fiber
