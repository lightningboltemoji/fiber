#include "fiber/browser/window/fiber_main_menu.h"

#import <AppKit/AppKit.h>

#include "chrome/app/chrome_command_ids.h"

namespace fiber {

namespace {

// The item tagged `tag` in `menu` or its submenus.
NSMenuItem* FindItemWithTag(NSMenu* menu, NSInteger tag) {
  for (NSMenuItem* item in menu.itemArray) {
    if (item.tag == tag) {
      return item;
    }
    if (NSMenuItem* found = FindItemWithTag(item.submenu, tag)) {
      return found;
    }
  }
  return nil;
}

}  // namespace

void InstallMainMenuItems() {
  static bool installed = false;
  NSMenu* view_menu = [NSApp.mainMenu itemWithTag:IDC_VIEW_MENU].submenu;
  if (installed || !view_menu) {
    return;
  }
  installed = true;

  FindItemWithTag(NSApp.mainMenu, IDC_SAVE_PAGE).keyEquivalentModifierMask =
      NSEventModifierFlagCommand | NSEventModifierFlagShift;

  // Titled and enabled by the window as it validates it.
  NSMenuItem* show_toolbar =
      [[NSMenuItem alloc] initWithTitle:@"Show Toolbar"
                                 action:@selector(toggleToolbarShown:)
                          keyEquivalent:@"s"];
  [view_menu insertItem:show_toolbar atIndex:0];
  [view_menu insertItem:NSMenuItem.separatorItem atIndex:1];
}

}  // namespace fiber
