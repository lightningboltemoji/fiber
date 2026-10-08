#include "fiber/browser/window/fiber_main_menu.h"

#import <AppKit/AppKit.h>

#import "FiberBridge/FiberWindow.h"
#include "chrome/app/chrome_command_ids.h"
#include "fiber/browser/sessions/previous_sessions_menu.h"

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
  // Fiber has no Task Manager, and Chrome's is a views window. With no window
  // open, AppController would still show it.
  NSMenuItem* task_manager =
      FindItemWithTag(NSApp.mainMenu, IDC_TASK_MANAGER_MAIN_MENU);
  [task_manager.menu removeItem:task_manager];

  // Titled and enabled by the window as it validates them.
  NSMenuItem* show_tabs =
      [[NSMenuItem alloc] initWithTitle:@"Show Tabs"
                                 action:@selector(toggleToolbarShown:)
                          keyEquivalent:@"s"];
  NSMenuItem* command_palette =
      [[NSMenuItem alloc] initWithTitle:@"Command Palette"
                                 action:@selector(toggleCommandPalette:)
                          keyEquivalent:@"p"];
  NSMenuItem* key_passthrough =
      [[NSMenuItem alloc] initWithTitle:@"Key Passthrough"
                                 action:@selector(toggleKeyPassthrough:)
                          keyEquivalent:@""];
  [view_menu insertItem:show_tabs atIndex:0];
  [view_menu insertItem:command_palette atIndex:1];
  [view_menu insertItem:key_passthrough atIndex:2];
  [view_menu insertItem:NSMenuItem.separatorItem atIndex:3];

  if (NSMenu* history_menu =
          [NSApp.mainMenu itemWithTag:IDC_HISTORY_MENU].submenu) {
    InstallPreviousSessionsMenu(history_menu);
  }

  // Opens Fiber's profile switcher. ProfileMenuController, which fills the
  // Profiles menu later or already has, keeps its profiles above the first
  // separator, so this goes below it, and has its own.
  NSMenu* profiles_menu =
      [NSApp.mainMenu itemWithTag:IDC_PROFILE_MAIN_MENU].submenu;
  if (profiles_menu) {
    NSMenuItem* switch_profile =
        [[NSMenuItem alloc] initWithTitle:@"Switch Profile…"
                                   action:@selector(commandDispatch:)
                            keyEquivalent:@"m"];
    switch_profile.keyEquivalentModifierMask =
        NSEventModifierFlagCommand | NSEventModifierFlagShift;
    switch_profile.tag = IDC_SHOW_AVATAR_MENU;
    NSInteger separator = [profiles_menu.itemArray
        indexOfObjectPassingTest:^BOOL(NSMenuItem* item, NSUInteger, BOOL*) {
          return item.separatorItem;
        }];
    if (separator == NSNotFound) {
      [profiles_menu addItem:NSMenuItem.separatorItem];
      [profiles_menu addItem:switch_profile];
    } else {
      [profiles_menu insertItem:switch_profile atIndex:separator + 1];
      [profiles_menu insertItem:NSMenuItem.separatorItem atIndex:separator + 2];
    }
  }
}

bool IsPassthroughItem(NSMenuItem* item) {
  return item.action == @selector(toggleToolbarShown:) ||
         item.action == @selector(toggleCommandPalette:) ||
         item.tag == IDC_FOCUS_LOCATION;
}

}  // namespace fiber
