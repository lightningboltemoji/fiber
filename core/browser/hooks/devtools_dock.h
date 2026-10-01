#ifndef FIBER_BROWSER_HOOKS_DEVTOOLS_DOCK_H_
#define FIBER_BROWSER_HOOKS_DEVTOOLS_DOCK_H_

class BrowserWindowInterface;

namespace content {
class WebContents;
}

// DevTools docked in Fiber's windows, in place of views' DevtoolsUIController,
// which only a BrowserView has.
namespace fiber {

// Whether DevTools for a page in `browser` can dock in its window. Called from
// DevToolsWindow::Create().
bool CanDockDevTools(BrowserWindowInterface* browser);

// Shows, moves or takes down what DevTools shows with `inspected_web_contents`
// (see DevToolsWindow::GetInTabWebContents()), if it's the active tab of a
// Fiber window. Called wherever DevToolsWindow updates DevtoolsUIController.
void UpdateDevTools(BrowserWindowInterface* browser,
                    content::WebContents* inspected_web_contents);

}  // namespace fiber

#endif  // FIBER_BROWSER_HOOKS_DEVTOOLS_DOCK_H_
