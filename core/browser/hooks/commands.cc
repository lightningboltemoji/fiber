#include "fiber/browser/hooks/commands.h"

#include "chrome/app/chrome_command_ids.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#include "fiber/browser/hooks/browser_window_factory.h"

namespace fiber {

bool IsCommandSupported(BrowserWindowInterface* browser, int command) {
  if (!IsFiberBrowser(browser)) {
    return true;
  }
  switch (command) {
    // Extension windows' bubbles have no find bar.
    case IDC_FIND:
    case IDC_FIND_NEXT:
    case IDC_FIND_PREVIOUS:
      return !IsExtensionWindowBubble(browser);
    // The app menu, and panes to focus.
    case IDC_FIND_AND_EDIT_MENU:
    case IDC_SHOW_APP_MENU:
    case IDC_FOCUS_TOOLBAR:
    case IDC_FOCUS_BOOKMARKS:
    case IDC_FOCUS_NEXT_PANE:
    case IDC_FOCUS_PREVIOUS_PANE:
    // Task Manager and the bookmark editor, views windows.
    case IDC_TASK_MANAGER_APP_MENU:
    case IDC_TASK_MANAGER_CONTEXT_MENU:
    case IDC_TASK_MANAGER_MAIN_MENU:
    case IDC_TASK_MANAGER_SHORTCUT:
    case IDC_BOOKMARK_ALL_TABS:
    // Pins are the profile's (fiber/browser/pins), which Incognito's has none
    // of.
    case IDC_WINDOW_PIN_TAB:
      return !browser->GetProfile()->IsOffTheRecord();
    // Selected, grouped and split tabs, which Fiber's tabs don't show.
    case IDC_PIN_TARGET_TAB:
    case IDC_WINDOW_GROUP_TAB:
    case IDC_GROUP_TARGET_TAB:
    case IDC_CREATE_NEW_TAB_GROUP:
    case IDC_ADD_NEW_TAB_TO_GROUP:
    case IDC_ADD_NEW_TAB_RECENT_GROUP:
    case IDC_CLOSE_TAB_GROUP:
    case IDC_FOCUS_NEXT_TAB_GROUP:
    case IDC_FOCUS_PREV_TAB_GROUP:
    case IDC_UNFOCUS_TAB_GROUP:
    case IDC_GROUP_UNGROUPED_TABS:
    case IDC_NEW_SPLIT_TAB:
    // Side panels, including the reading list's.
    case IDC_SHOW_BOOKMARK_SIDE_PANEL:
    case IDC_SHOW_HISTORY_CLUSTERS_SIDE_PANEL:
    case IDC_SHOW_TABS_FROM_OTHER_DEVICES_SIDE_PANEL:
    case IDC_SHOW_COMMENTS_SIDE_PANEL:
    case IDC_SHOW_CUSTOMIZE_CHROME_SIDE_PANEL:
    case IDC_SHOW_CUSTOMIZE_CHROME_TOOLBAR:
    case IDC_READING_LIST_MENU_ADD_TAB:
    case IDC_READING_LIST_MENU_SHOW_UI:
    // Bubbles on the toolbar, and installing web apps.
    case IDC_QRCODE_GENERATOR:
    case IDC_SEND_TAB_TO_SELF:
    case IDC_SHARING_HUB:
    case IDC_SHARING_HUB_SCREENSHOT:
    case IDC_INSTALL_PWA:
    case IDC_CREATE_SHORTCUT:
      return false;
    default:
      return true;
  }
}

}  // namespace fiber
