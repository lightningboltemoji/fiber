#include "fiber/browser/hooks/confirm_quit.h"

#import <AppKit/AppKit.h>

#import "FiberBridge/FiberQuitConfirmation.h"
#include "base/functional/bind.h"
#include "base/memory/weak_ptr.h"
#include "base/no_destructor.h"
#include "base/strings/sys_string_conversions.h"
#include "chrome/app/chrome_command_ids.h"
#import "chrome/browser/chrome_browser_application_mac.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface_iterator.h"
#include "chrome/browser/ui/browser_window/public/create_browser_window.h"
#include "chrome/browser/ui/browser_window.h"
#include "chrome/grit/generated_resources.h"
#include "fiber/browser/downloads/downloads_wait.h"
#include "ui/base/accelerators/accelerator.h"
#include "ui/base/l10n/l10n_util_mac.h"
#include "ui/events/cocoa/cocoa_event_utils.h"
#include "ui/events/keycodes/keyboard_code_conversion_mac.h"

namespace fiber {

namespace {

// The app menu's Quit item, or Command-Q's if it has none.
NSMenuItem* QuitMenuItem() {
  NSMenu* app_menu = [NSApp.mainMenu itemAtIndex:0].submenu;
  for (NSMenuItem* item in app_menu.itemArray) {
    if (item.tag == IDC_EXIT) {
      return item;
    }
  }
  NSMenuItem* item =
      [[NSMenuItem alloc] initWithTitle:@""
                                 action:@selector(commandDispatch:)
                          keyEquivalent:@"q"];
  item.tag = IDC_EXIT;
  item.keyEquivalentModifierMask = NSEventModifierFlagCommand;
  return item;
}

}  // namespace

bool ConfirmQuit(NSEvent* event) {
  NSString* announcement = l10n_util::GetNSStringF(
      IDS_CONFIRM_TO_QUIT_DESCRIPTION,
      base::SysNSStringToUTF16(QuitKeyCommandString()));
  return [FiberQuitConfirmation runWithEvent:event announcement:announcement];
}

void CancelConfirmQuit() {
  [FiberQuitConfirmation restoreWindows];
}

void WaitForDownloadsBeforeQuitting(const std::vector<Profile*>& profiles) {
  // Quitting again while waiting leaves the wait as it is.
  static base::NoDestructor<base::WeakPtr<DownloadsWait>> wait;
  if (*wait || profiles.empty()) {
    return;
  }
  BrowserWindowInterface* browser =
      GetLastActiveBrowserWindowInterfaceWithAnyProfile();
  if (!browser) {
    browser = CreateBrowserWindow(
        BrowserWindowCreateParams(*profiles.front(), /*from_user_gesture=*/true));
    browser->GetWindow()->Show();
  }
  *wait = DownloadsWait::Start(
      DownloadsWait::Reason::kQuit, profiles,
      browser->GetWindow()->GetNativeWindow(),
      base::BindOnce([](bool proceed) {
        if (proceed) {
          chrome_browser_application_mac::Terminate();
        } else {
          CancelConfirmQuit();
        }
      }));
}

NSString* QuitKeyCommandString() {
  NSMenuItem* item = QuitMenuItem();
  ui::Accelerator accelerator(
      ui::KeyboardCodeFromCharCode([item.keyEquivalent characterAtIndex:0]),
      ui::EventFlagsFromModifiers(item.keyEquivalentModifierMask));
  return base::SysUTF16ToNSString(accelerator.GetShortcutText());
}

}  // namespace fiber
