#ifndef FIBER_BROWSER_HOOKS_FEATURE_OVERRIDES_H_
#define FIBER_BROWSER_HOOKS_FEATURE_OVERRIDES_H_

#include <vector>

#include "base/feature_list.h"

namespace fiber {

// Adds Fiber's defaults for Chrome features to `overrides`. They take
// precedence over field trials, but not over --enable-features and
// --disable-features. Called from ChromeFeatureListCreator::SetUpFieldTrials()
// (see patches/chromium/
// chrome-browser-metrics-chrome_feature_list_creator.cc.patch).
void AddFeatureOverrides(
    std::vector<base::FeatureList::FeatureOverrideInfo>& overrides);

}  // namespace fiber

#endif  // FIBER_BROWSER_HOOKS_FEATURE_OVERRIDES_H_
