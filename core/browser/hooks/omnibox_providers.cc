#include "fiber/browser/hooks/omnibox_providers.h"

#include "components/omnibox/browser/autocomplete_provider.h"

namespace fiber {

int OmniboxProviderTypes(int chrome_providers) {
  // Suggestions only Google provides: they send it the page or what's typed
  // (zero-suggest, Lens's contextual search), or need a Google account (Drive
  // documents, other devices' tabs) or a Google-hosted service or model.
  constexpr int kLeftOut =
      AutocompleteProvider::TYPE_ZERO_SUGGEST |
      AutocompleteProvider::TYPE_CONTEXTUAL_SEARCH |
      AutocompleteProvider::TYPE_DOCUMENT |
      AutocompleteProvider::TYPE_CROSS_DEVICE_TAB |
      AutocompleteProvider::TYPE_ENTERPRISE_SEARCH_AGGREGATOR |
      AutocompleteProvider::TYPE_ON_DEVICE_HEAD |
      AutocompleteProvider::TYPE_HISTORY_EMBEDDINGS;
  return chrome_providers & ~kLeftOut;
}

}  // namespace fiber
