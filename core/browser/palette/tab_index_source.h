#ifndef FIBER_BROWSER_PALETTE_TAB_INDEX_SOURCE_H_
#define FIBER_BROWSER_PALETTE_TAB_INDEX_SOURCE_H_

#include <map>
#include <memory>
#include <optional>
#include <string>
#include <vector>

#include "base/memory/raw_ptr.h"
#include "base/memory/weak_ptr.h"
#include "base/scoped_observation.h"
#include "components/sessions/core/tab_restore_service.h"
#include "components/sessions/core/tab_restore_service_observer.h"
#include "fiber/browser/sessions/previous_sessions.h"

@protocol FiberTabIndex;
class BrowserWindowInterface;
class Profile;

namespace content {
class WebContents;
}

namespace fiber {

class FiberBrowserWindow;
class PageText;

// Fills a profile's FiberTabIndex, which the command palettes of its windows
// search: the tabs of all its Fiber windows, their pages' text, the windows
// the user closed (Chrome's recently closed), and its previous sessions. Made
// with the profile's first window, and deleted with its last.
class TabIndexSource : public sessions::TabRestoreServiceObserver,
                       public PreviousSessions::Observer {
 public:
  TabIndexSource(const TabIndexSource&) = delete;
  TabIndexSource& operator=(const TabIndexSource&) = delete;
  ~TabIndexSource() override;

  // The source for `window`'s profile, which now includes `window`.
  static TabIndexSource* AddWindow(FiberBrowserWindow* window);
  static void RemoveWindow(FiberBrowserWindow* window);

  id<FiberTabIndex> index() const { return index_; }

  // A window's tabs changed: the index gets all of them, soon.
  void TabsChanged();
  // Reads the text of the tab's page now, for the command palette opening.
  void ReadPageText(content::WebContents* web_contents);
  // Finds `text` in the tab's page, leaving it selected.
  void RevealText(content::WebContents* web_contents,
                  const std::u16string& text);
  // Reads the previous sessions kept since, for the command palette opening.
  void UpdatePreviousSessions();
  // Brings back what `restorable_id` names in the index, showing page
  // `page_index` of a closed window's.
  void Restore(BrowserWindowInterface* browser,
               const std::string& restorable_id,
               std::optional<size_t> page_index);

  // sessions::TabRestoreServiceObserver:
  void TabRestoreServiceChanged(sessions::TabRestoreService* service) override;
  void TabRestoreServiceDestroyed(
      sessions::TabRestoreService* service) override;
  void TabRestoreServiceLoaded(sessions::TabRestoreService* service) override;

  // PreviousSessions::Observer:
  void OnPreviousSessionsChanged() override;

 private:
  explicit TabIndexSource(Profile* profile);

  static std::vector<std::unique_ptr<TabIndexSource>>& All();

  void SendTabs();
  PageText* PageTextFor(content::WebContents* web_contents);
  // Windows closed, and previous sessions not all open now, changed: the
  // index gets them, soon.
  void RestorablesChanged();
  void SendRestorables();
  void RestoreClosedWindow(BrowserWindowInterface* browser,
                           SessionID id,
                           std::optional<size_t> page_index);

  const raw_ptr<Profile> profile_;
  std::vector<raw_ptr<FiberBrowserWindow>> windows_;
  id<FiberTabIndex> __strong index_;
  // By tab ID.
  std::map<int32_t, std::unique_ptr<PageText>> page_texts_;
  bool is_send_pending_ = false;
  bool is_restorables_send_pending_ = false;
  std::vector<std::string> sent_restorable_ids_;
  // Null for an Incognito or Guest profile.
  raw_ptr<PreviousSessions> previous_sessions_;
  base::ScopedObservation<sessions::TabRestoreService,
                          sessions::TabRestoreServiceObserver>
      tab_restore_observation_{this};
  base::ScopedObservation<PreviousSessions, PreviousSessions::Observer>
      previous_sessions_observation_{this};
  base::WeakPtrFactory<TabIndexSource> weak_factory_{this};
};

}  // namespace fiber

#endif  // FIBER_BROWSER_PALETTE_TAB_INDEX_SOURCE_H_
