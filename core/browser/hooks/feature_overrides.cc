#include "fiber/browser/hooks/feature_overrides.h"

#include <functional>

#include "chrome/browser/media/router/media_router_feature.h"
#include "chrome/browser/preloading/prefetch/search_prefetch/field_trial_settings.h"
#include "chrome/browser/preloading/preloading_features.h"
#include "chrome/common/chrome_features.h"
#include "components/autofill/core/common/autofill_features.h"
#include "components/omnibox/browser/aim_eligibility_service_features.h"
#include "components/security_interstitials/core/features.h"
#include "content/public/common/content_features.h"

namespace fiber {

void AddFeatureOverrides(
    std::vector<base::FeatureList::FeatureOverrideInfo>& overrides) {
  const base::Feature* disabled[] = {
      // The omnibox's requests to the search engine that the user didn't ask
      // for, like those made while typing, before they've searched for
      // anything:
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
      // Gemini in Chrome (Glic), which needs a Google account and whose pages
      // Fiber cuts. On, Chrome offers it to signed-out profiles too.
      &features::kGlic,
      // HTTPS-First's views dialog before loading a site over HTTP; its
      // warning page shows in the tab instead.
      &security_interstitials::features::kHttpsFirstDialogUi,
      // Web APIs whose only UI is views', which Fiber doesn't have yet, so
      // pages don't find them: Payment Request (with Secure Payment
      // Confirmation), digital credentials, and Cast with the Presentation
      // API. Patches cut their code: turned back on with a flag, they fail
      // (Cast crashes).
      &features::kWebPayments,
      &features::kWebIdentityDigitalCredentials,
      &features::kWebIdentityDigitalCredentialsCreation,
      &media_router::kMediaRouter,
      // Google Wallet's passes in autofill, which come from a Google account.
      // For them, every new tab asks macOS whether Touch ID is available: a
      // few milliseconds on the main thread, the first as Fiber starts.
      &autofill::features::kAutofillAiWalletPrivatePasses,
  };
  for (const base::Feature* feature : disabled) {
    overrides.emplace_back(std::cref(*feature),
                           base::FeatureList::OVERRIDE_DISABLE_FEATURE);
  }
}

}  // namespace fiber
