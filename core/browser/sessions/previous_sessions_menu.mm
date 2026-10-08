#include "fiber/browser/sessions/previous_sessions_menu.h"

#import <AppKit/AppKit.h>

#include "base/apple/foundation_util.h"
#include "base/files/file_path.h"
#include "chrome/app/chrome_command_ids.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/profiles/profile_manager.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#include "chrome/browser/ui/browser_window/public/global_browser_collection.h"
#include "fiber/browser/sessions/previous_sessions.h"

namespace {

// The last active window's profile, or with none open, the last used.
fiber::PreviousSessions* MenuSessions() {
  BrowserWindowInterface* browser =
      GlobalBrowserCollection::GetInstance()->GetLastActiveBrowser();
  return fiber::PreviousSessions::FromProfile(
      browser ? browser->GetProfile()->GetOriginalProfile()
              : ProfileManager::GetLastUsedProfileIfLoaded());
}

NSString* Count(size_t count, NSString* one, NSString* many) {
  return [NSString stringWithFormat:@"%zu %@", count, count == 1 ? one : many];
}

}  // namespace

@interface FiberPreviousSessionsMenu : NSObject <NSMenuDelegate>
@end

@implementation FiberPreviousSessionsMenu {
  NSDateFormatter* _formatter;
}

- (instancetype)init {
  if ((self = [super init])) {
    _formatter = [[NSDateFormatter alloc] init];
    _formatter.dateStyle = NSDateFormatterMediumStyle;
    _formatter.timeStyle = NSDateFormatterShortStyle;
    _formatter.doesRelativeDateFormatting = YES;
  }
  return self;
}

- (void)menuNeedsUpdate:(NSMenu*)menu {
  [menu removeAllItems];
  if (fiber::PreviousSessions* sessions = MenuSessions()) {
    // For next time, in case any were kept since.
    sessions->Update();
    for (const fiber::PreviousSessions::Session* session :
         sessions->Offered()) {
      NSMenuItem* item = [[NSMenuItem alloc]
          initWithTitle:[_formatter stringFromDate:session->ended.ToNSDate()]
                 action:@selector(restoreSession:)
          keyEquivalent:@""];
      item.target = self;
      if (@available(macOS 14.4, *)) {
        item.subtitle = [NSString
            stringWithFormat:@"%@, %@",
                             Count(session->windows.size(), @"window",
                                   @"windows"),
                             Count(session->TabCount(), @"tab", @"tabs")];
      }
      item.representedObject = base::apple::FilePathToNSString(session->path);
      [menu addItem:item];
    }
  }
  if (menu.numberOfItems == 0) {
    [menu addItemWithTitle:@"No Previous Sessions"
                    action:nil
             keyEquivalent:@""];
  }
}

- (void)restoreSession:(NSMenuItem*)item {
  if (fiber::PreviousSessions* sessions = MenuSessions()) {
    sessions->Restore(base::apple::NSStringToFilePath(item.representedObject));
  }
}

@end

namespace fiber {

void InstallPreviousSessionsMenu(NSMenu* history_menu) {
  NSInteger index = [history_menu indexOfItemWithTag:IDC_SHOW_HISTORY];
  if (index == -1) {
    return;
  }
  static FiberPreviousSessionsMenu* delegate =
      [[FiberPreviousSessionsMenu alloc] init];
  NSMenu* submenu = [[NSMenu alloc] initWithTitle:@"Previous Sessions"];
  submenu.delegate = delegate;
  NSMenuItem* item = [[NSMenuItem alloc] initWithTitle:@"Previous Sessions"
                                                action:nil
                                         keyEquivalent:@""];
  item.tag = kPreviousSessionsMenuTag;
  item.submenu = submenu;
  [history_menu insertItem:item atIndex:index];
}

}  // namespace fiber
