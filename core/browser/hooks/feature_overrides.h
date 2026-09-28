#ifndef FIBER_BROWSER_HOOKS_FEATURE_OVERRIDES_H_
#define FIBER_BROWSER_HOOKS_FEATURE_OVERRIDES_H_

#include <vector>

#include "base/feature_list.h"

namespace fiber {

// Fiber's feature defaults, outranking field trials but not command-line flags.
// Called from ChromeFeatureListCreator::SetUpFieldTrials() (see patches/
// chromium/chrome-browser-metrics-chrome_feature_list_creator.cc.patch).
void AddFeatureOverrides(
    std::vector<base::FeatureList::FeatureOverrideInfo>& overrides);

}  // namespace fiber

#endif  // FIBER_BROWSER_HOOKS_FEATURE_OVERRIDES_H_
