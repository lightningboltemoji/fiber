#include "fiber/browser/hooks/omnibox_providers.h"

#include "components/omnibox/browser/autocomplete_provider.h"

namespace fiber {

int OmniboxProviderTypes(int chrome_providers) {
  // Suggestions that only come from Google: they send it the page or what's
  // typed (zero-suggest sends the current URL; contextual search is Lens's
  // "Ask Google about this page"), need a Google account (Drive documents,
  // other devices' tabs), or a Google-hosted service or model (enterprise
  // search, the on-device suggestion model, history embeddings).
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
