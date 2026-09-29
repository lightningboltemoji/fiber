#include "fiber/browser/window/fiber_main_menu.h"

#import <AppKit/AppKit.h>

#import "FiberBridge/FiberWindow.h"
#include "chrome/app/chrome_command_ids.h"

namespace fiber {

namespace {

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
  // Printing is always with the system's panel (see profile_pref_defaults.cc),
  // so Print Using System Dialog, Print's Option alternate, is Print.
  NSMenuItem* basic_print = FindItemWithTag(NSApp.mainMenu, IDC_BASIC_PRINT);
  [basic_print.menu removeItem:basic_print];
  FindItemWithTag(NSApp.mainMenu, IDC_PRINT).keyEquivalentModifierMask =
      NSEventModifierFlagCommand | NSEventModifierFlagOption;

  // Titled and enabled by the window as it validates them.
  NSMenuItem* show_toolbar =
      [[NSMenuItem alloc] initWithTitle:@"Show Toolbar"
                                 action:@selector(toggleToolbarShown:)
                          keyEquivalent:@"s"];
  NSMenuItem* command_palette =
      [[NSMenuItem alloc] initWithTitle:@"Command Palette"
                                 action:@selector(toggleCommandPalette:)
                          keyEquivalent:@"p"];
  [view_menu insertItem:show_toolbar atIndex:0];
  [view_menu insertItem:command_palette atIndex:1];
  [view_menu insertItem:NSMenuItem.separatorItem atIndex:2];
}

}  // namespace fiber
