#include "fiber/browser/hooks/omnibox_providers.h"

#include "components/omnibox/browser/autocomplete_provider.h"

namespace fiber {

int OmniboxProviderTypes(int chrome_providers) {
  // Suggestions only Google provides: they send it the page or what's typed
  // (zero-suggest, Lens's contextual search), or need a Google account (Drive
  // documents, other devices' tabs) or a Google-hosted service or model.
  constexpr int kLeftOut =
      static_cast<int>(AutocompleteProvider::Type::kZeroSuggest |
                       AutocompleteProvider::Type::kContextualSearch |
                       AutocompleteProvider::Type::kDocument |
                       AutocompleteProvider::Type::kCrossDeviceTab |
                       AutocompleteProvider::Type::kEnterpriseSearchAggregator |
                       AutocompleteProvider::Type::kOnDeviceHead |
                       AutocompleteProvider::Type::kHistoryEmbeddings);
  return chrome_providers & ~kLeftOut;
}

}  // namespace fiber
