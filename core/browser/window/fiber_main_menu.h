#ifndef FIBER_BROWSER_WINDOW_FIBER_MAIN_MENU_H_
#define FIBER_BROWSER_WINDOW_FIBER_MAIN_MENU_H_

@class NSMenuItem;

namespace fiber {

// Adds Fiber's items to Chrome's main menu, once: View > Show Toolbar
// (Command-S), View > Command Palette (Command-P) and View > Key Passthrough,
// which the key Fiber window handles (see FiberWindow.h). Save Page As… moves
// to Shift-Command-S and Print… to Option-Command-P to make room.
void InstallMainMenuItems();

// Show Tabs, Command Palette and Open Location, whose shortcuts pages only get
// with key passthrough (see key_passthrough.h).
bool IsPassthroughItem(NSMenuItem* item);

}  // namespace fiber

#endif  // FIBER_BROWSER_WINDOW_FIBER_MAIN_MENU_H_
