#include "fiber/browser/hooks/feature_overrides.h"

#include <functional>

#include "chrome/browser/preloading/prefetch/search_prefetch/field_trial_settings.h"
#include "chrome/browser/preloading/preloading_features.h"
#include "components/omnibox/browser/aim_eligibility_service_features.h"

namespace fiber {

void AddFeatureOverrides(
    std::vector<base::FeatureList::FeatureOverrideInfo>& overrides) {
  // The omnibox's requests to the search engine that the user didn't ask for,
  // like those made while typing, before they've searched for anything:
  const base::Feature* disabled[] = {
      // Loads a search results page in the background.
      &features::kPrewarm,
      // Fetches results for the top suggestion, and for the selected one on
      // arrow keys and mouse down.
      &kSearchPrefetchServicePrefetching,
      &kSearchNavigationPrefetch,
      // Fetches a compression dictionary from the search engine.
      &kAutocompleteDictionaryPreload,
      // Google's AI Mode, and the request asking Google whether the user can
      // have it (at startup, and when accounts or cookies change).
      &omnibox::kAimEnabled,
  };
  for (const base::Feature* feature : disabled) {
    overrides.emplace_back(std::cref(*feature),
                           base::FeatureList::OVERRIDE_DISABLE_FEATURE);
  }
}

}  // namespace fiber
