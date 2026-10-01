#ifndef FIBER_BROWSER_PINS_PINNED_TAB_DATA_H_
#define FIBER_BROWSER_PINS_PINNED_TAB_DATA_H_

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

}  // namespace fiber

#endif  // FIBER_BROWSER_PINS_PINNED_TAB_DATA_H_
