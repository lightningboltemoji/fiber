#ifndef FIBER_BROWSER_WINDOW_KEY_PASSTHROUGH_H_
#define FIBER_BROWSER_WINDOW_KEY_PASSTHROUGH_H_

namespace content {
class WebContents;
}

namespace fiber {

// Key passthrough: the tab's page and DevTools get Command-S, Command-P and
// Command-L, which Fiber otherwise keeps from them (see
// PerformReservedKeyEquivalent()), until the user ends it or it changes site.
bool HasKeyPassthrough(content::WebContents* contents);
void StartKeyPassthrough(content::WebContents* contents);
void EndKeyPassthrough(content::WebContents* contents);

}  // namespace fiber

#endif  // FIBER_BROWSER_WINDOW_KEY_PASSTHROUGH_H_
