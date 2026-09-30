#ifndef FIBER_BROWSER_HOOKS_RESOURCE_BUNDLE_DELEGATE_H_
#define FIBER_BROWSER_HOOKS_RESOURCE_BUNDLE_DELEGATE_H_

#include "ui/base/resource/resource_bundle.h"

namespace fiber {

// Gives Fiber's app icon for Chrome's product logos (the About page's, among
// others). InitResourceBundleAndDetermineLocale() passes it to ResourceBundle
// (see patches/chromium/chrome-browser-chrome_resource_bundle_helper.cc.patch).
ui::ResourceBundle::Delegate* GetResourceBundleDelegate();

}  // namespace fiber

#endif  // FIBER_BROWSER_HOOKS_RESOURCE_BUNDLE_DELEGATE_H_
