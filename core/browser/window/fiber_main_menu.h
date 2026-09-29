#ifndef FIBER_BROWSER_WINDOW_FIBER_MAIN_MENU_H_
#define FIBER_BROWSER_WINDOW_FIBER_MAIN_MENU_H_

namespace fiber {

// Adds Fiber's items to Chrome's main menu, once: View > Show Toolbar
// (Command-S) and View > Command Palette (Command-P), which the key Fiber
// window handles (see FiberWindow.h). Save Page As… moves to Shift-Command-S
// and Print… to Option-Command-P to make room.
void InstallMainMenuItems();

}  // namespace fiber

#endif  // FIBER_BROWSER_WINDOW_FIBER_MAIN_MENU_H_
