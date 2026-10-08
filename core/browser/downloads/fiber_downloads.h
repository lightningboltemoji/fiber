#ifndef FIBER_BROWSER_DOWNLOADS_FIBER_DOWNLOADS_H_
#define FIBER_BROWSER_DOWNLOADS_FIBER_DOWNLOADS_H_

#include <optional>
#include <string>
#include <vector>

#include "base/memory/raw_ptr.h"
#include "base/memory/weak_ptr.h"
#include "chrome/browser/download/download_commands.h"
#include "components/download/content/public/all_download_item_notifier.h"

@class FiberDownloadsActionsBridge;
@protocol FiberDownloads;

class BrowserWindowInterface;

namespace fiber {

// A Fiber window's downloads (FiberDownloads in the bridge), in its tab
// overlay: its profile's recent ones, and what the user does with them, as
// Chrome's download bubble does.
class FiberDownloads : public download::AllDownloadItemNotifier::Observer {
 public:
  FiberDownloads(BrowserWindowInterface* browser, id<FiberDownloads> ui);
  FiberDownloads(const FiberDownloads&) = delete;
  FiberDownloads& operator=(const FiberDownloads&) = delete;
  ~FiberDownloads() override;

  // Called by the UI's actions, with a download's GUID.
  void Open(const std::string& guid);
  void ShowInFinder(const std::string& guid);
  void Pause(const std::string& guid);
  void Resume(const std::string& guid);
  void Cancel(const std::string& guid);
  void Retry(const std::string& guid);
  void Keep(const std::string& guid);
  void Discard(const std::string& guid);
  void Remove(const std::string& guid);
  void Clear();
  void ShowAll();
  void OnShown();

  // download::AllDownloadItemNotifier::Observer:
  void OnManagerInitialized(content::DownloadManager* manager) override;
  void OnDownloadCreated(content::DownloadManager* manager,
                         download::DownloadItem* item) override;
  void OnDownloadUpdated(content::DownloadManager* manager,
                         download::DownloadItem* item) override;
  void OnDownloadRemoved(content::DownloadManager* manager,
                         download::DownloadItem* item) override;
  void OnDownloadDestroyed(content::DownloadManager* manager,
                           download::DownloadItem* item) override;

 private:
  download::DownloadItem* FindDownload(const std::string& guid) const;
  // Runs `command` on the download if it can take it now.
  void ExecuteCommand(const std::string& guid,
                      DownloadCommands::Command command);
  // The downloads the UI lists, in its order.
  std::vector<download::DownloadItem*> ListedDownloads() const;

  // Sends the UI the downloads soon, coalescing a burst of updates.
  void ScheduleUpdate();
  void Update();

  const raw_ptr<BrowserWindowInterface> browser_;
  id<FiberDownloads> __weak ui_;
  FiberDownloadsActionsBridge* __strong actions_;
  bool update_scheduled_ = false;
  // Made in the constructor's body, once the rest is: it calls back as it's
  // made.
  std::optional<download::AllDownloadItemNotifier> notifier_;
  base::WeakPtrFactory<FiberDownloads> weak_factory_{this};
};

}  // namespace fiber

#endif  // FIBER_BROWSER_DOWNLOADS_FIBER_DOWNLOADS_H_
