#ifndef FIBER_BROWSER_PINS_PINNED_TAB_DATA_H_
#define FIBER_BROWSER_PINS_PINNED_TAB_DATA_H_

#include <map>
#include <string>
#include <string_view>

namespace content {
class WebContents;
}

namespace fiber {

// The ID of the pin (see PinStore) whose page the tab is, or empty. It's kept
// in the tab's session, so a restored tab is still its pin's.
std::string PinIDForTab(content::WebContents* contents);
// Empty makes it no pin's.
void SetPinIDForTab(content::WebContents* contents, std::string_view pin_id);

// Whether the tab is pinned only to be on the right of a split with a pin's
// tab, which Chrome's split has share its pinning (see split/tab_split.h).
// It's no pin's. Also kept in its session.
bool IsBesidePin(content::WebContents* contents);
void SetBesidePin(content::WebContents* contents, bool beside);

// Both, for the tab's session and closed-tab history (see
// hooks/tab_extra_data.h).
void AddPinExtraData(content::WebContents* contents,
                     std::map<std::string, std::string>& extra_data);
void RestorePinExtraData(content::WebContents* contents,
                         const std::map<std::string, std::string>& extra_data);

}  // namespace fiber

#endif  // FIBER_BROWSER_PINS_PINNED_TAB_DATA_H_
