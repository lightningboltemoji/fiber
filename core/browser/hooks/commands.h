#ifndef FIBER_BROWSER_HOOKS_COMMANDS_H_
#define FIBER_BROWSER_HOOKS_COMMANDS_H_

class BrowserWindowInterface;

namespace fiber {

// Whether `browser` can run `command`: in a Fiber window, not those whose UI
// Fiber doesn't have yet, which Chrome shows with views. Called from
// BrowserCommandController::IsCommandEnabled(), so it covers every way in.
bool IsCommandSupported(BrowserWindowInterface* browser, int command);

}  // namespace fiber

#endif  // FIBER_BROWSER_HOOKS_COMMANDS_H_
