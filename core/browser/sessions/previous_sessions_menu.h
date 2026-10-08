#ifndef FIBER_BROWSER_SESSIONS_PREVIOUS_SESSIONS_MENU_H_
#define FIBER_BROWSER_SESSIONS_PREVIOUS_SESSIONS_MENU_H_

@class NSMenu;

namespace fiber {

// Its tag. The History menu's are its own (HistoryMenuBridge::Tags), and
// HistoryMenuBridge shows or hides each by its tag.
inline constexpr int kPreviousSessionsMenuTag = 500;

// Adds History › Previous Sessions, above Show Full History: the previous
// sessions of the profile last used (see PreviousSessions), which it fills as
// it opens, each reopening its windows.
void InstallPreviousSessionsMenu(NSMenu* history_menu);

}  // namespace fiber

#endif  // FIBER_BROWSER_SESSIONS_PREVIOUS_SESSIONS_MENU_H_
