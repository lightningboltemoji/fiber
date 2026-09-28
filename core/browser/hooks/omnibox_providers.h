#ifndef FIBER_BROWSER_HOOKS_OMNIBOX_PROVIDERS_H_
#define FIBER_BROWSER_HOOKS_OMNIBOX_PROVIDERS_H_

namespace fiber {

// The omnibox's providers (AutocompleteProvider::Type bits): `chrome_providers`
// less those Fiber leaves out. Called from OmniboxController's constructor (see
// patches/chromium/chrome-browser-ui-omnibox-omnibox_controller.cc.patch).
int OmniboxProviderTypes(int chrome_providers);

}  // namespace fiber

#endif  // FIBER_BROWSER_HOOKS_OMNIBOX_PROVIDERS_H_
