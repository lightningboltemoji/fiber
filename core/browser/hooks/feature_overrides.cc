#include "fiber/browser/hooks/feature_overrides.h"

#include <functional>

#include "chrome/browser/media/router/media_router_feature.h"
#include "chrome/browser/preloading/prefetch/search_prefetch/field_trial_settings.h"
#include "chrome/browser/preloading/preloading_features.h"
#include "chrome/browser/ui/ui_features.h"
#include "chrome/common/chrome_features.h"
#include "components/autofill/core/common/autofill_features.h"
#include "components/contextual_tasks/public/features.h"
#include "components/feature_engagement/public/feature_constants.h"
#include "components/lens/lens_features.h"
#include "components/omnibox/browser/aim_eligibility_service_features.h"
#include "components/optimization_guide/core/delivery/prediction_model_component_configs.h"
#include "components/security_interstitials/core/features.h"
#include "content/public/common/content_features.h"
#include "extensions/common/extension_features.h"
#include "third_party/blink/public/common/features_generated.h"
#include "ui/accessibility/accessibility_features.h"

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
      // Glic's component extension, which google.com's pages can message.
      &extensions_features::kApiGlicPrivate,
      // Contextual tasks' side panel, and the Lens results that go to it: its
      // throttle takes AI Mode pages out of the tab, for a panel Fiber doesn't
      // have.
      &contextual_tasks::kContextualTasksSidePanel,
      &lens::features::kLensSidePanelUnification,
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
      // The email verification protocol, whose only UI is a views popup, and
      // which asks the address's provider (Google, for Gmail) before showing
      // it.
      &features::kEmailVerificationProtocol,
      // Chrome's infobar about restoring on startup, which Fiber does by
      // default and always after a crash, and which Fiber has no UI for.
      &features::kSessionRestoreInfobar,
      // Google Wallet's passes in autofill, which come from a Google account.
      // For them, every new tab asks macOS whether Touch ID is available: a
      // few milliseconds on the main thread, the first as Fiber starts.
      &autofill::features::kAutofillAiWalletPrivatePasses,
      // Chrome's promos for its split view's toolbar button, which Fiber's
      // split doesn't have.
      &feature_engagement::kIPHSideBySidePinnableFeature,
      &feature_engagement::kIPHSideBySideTabSwitchFeature,
      // navigator.install() and <install>: Fiber doesn't offer installing a
      // page as an app, so pages don't find them.
      &blink::features::kWebAppInstallation,
      &blink::features::kInstallElement,
      // Chrome's install dialog with custom views, which Fiber's prompts can't
      // show, for the ways to install that remain.
      &features::kWebAppInstallDialog,
      // Pinning an extension as it installs, which Fiber's install prompt
      // offers as a choice.
      &features::kExtensionsPinnedByDefault,
      // Reading mode's chip, which the omnibar doesn't have.
      &features::kReadAnythingOmniboxChip,
      // Downloads permission prediction models Fiber's prompts don't use.
      &optimization_guide::kPredictionModelComponentDelivery,
      // Restarting unasked as the screen locks, once a newer version is
      // installed.
      &features::kSmartRestartLockScreen,
  };
  for (const base::Feature* feature : disabled) {
    overrides.emplace_back(std::cref(*feature),
                           base::FeatureList::OVERRIDE_DISABLE_FEATURE);
  }
}

}  // namespace fiber
