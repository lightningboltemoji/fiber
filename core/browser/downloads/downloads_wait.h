#ifndef FIBER_BROWSER_DOWNLOADS_DOWNLOADS_WAIT_H_
#define FIBER_BROWSER_DOWNLOADS_DOWNLOADS_WAIT_H_

#include <memory>
#include <string>
#include <vector>

#include "base/functional/callback.h"
#include "base/memory/weak_ptr.h"
#include "components/download/content/public/all_download_item_notifier.h"
#include "ui/gfx/native_ui_types.h"

@class FiberDownloadsWaitActionsBridge;
@protocol FiberDownloadsWait;
class Profile;

namespace fiber {

// A quit, or a window's close, waiting for downloads to finish, listed over
// the page by FiberDownloadsWaitFactory. Owns itself until it's done.
class DownloadsWait : public download::AllDownloadItemNotifier::Observer {
 public:
  enum class Reason {
    kQuit,
    kCloseWindow,
  };

  // Waits for the downloads in `profiles` that would block shutdown. Runs
  // `done` with true once none are left (ProceedNow() cancels the rest), or
  // with false if the user stops waiting or the wait is closed.
  static base::WeakPtr<DownloadsWait> Start(
      Reason reason,
      const std::vector<Profile*>& profiles,
      gfx::NativeWindow window,
      base::OnceCallback<void(bool)> done);

  DownloadsWait(const DownloadsWait&) = delete;
  DownloadsWait& operator=(const DownloadsWait&) = delete;

  // Called by the UI's actions.
  void CancelDownload(const std::string& guid);
  void ResumeDownload(const std::string& guid);
  void ProceedNow();
  void StopWaiting();

  // Stops waiting, as if the user had.
  void Close();

  // download::AllDownloadItemNotifier::Observer:
  void OnDownloadCreated(content::DownloadManager* manager,
                         download::DownloadItem* item) override;
  void OnDownloadUpdated(content::DownloadManager* manager,
                         download::DownloadItem* item) override;
  void OnDownloadRemoved(content::DownloadManager* manager,
                         download::DownloadItem* item) override;
  void OnDownloadDestroyed(content::DownloadManager* manager,
                           download::DownloadItem* item) override;

 private:
  DownloadsWait(const std::vector<Profile*>& profiles,
                base::OnceCallback<void(bool)> done);
  ~DownloadsWait() override;

  // The downloads still being waited for, in the order they started.
  std::vector<download::DownloadItem*> BlockingDownloads() const;
  download::DownloadItem* FindDownload(const std::string& guid) const;

  // Sends the UI the downloads soon, coalescing a burst of updates.
  void ScheduleUpdate();
  // Sends the UI the downloads, or finishes if there are none.
  void Update();
  // Takes the UI down, runs `done_` with `proceed`, and deletes this.
  void Finish(bool proceed);

  std::vector<std::unique_ptr<download::AllDownloadItemNotifier>> notifiers_;
  base::OnceCallback<void(bool)> done_;
  FiberDownloadsWaitActionsBridge* __strong actions_;
  id<FiberDownloadsWait> __strong ui_;
  bool update_scheduled_ = false;
  base::WeakPtrFactory<DownloadsWait> weak_factory_{this};
};

}  // namespace fiber

#endif  // FIBER_BROWSER_DOWNLOADS_DOWNLOADS_WAIT_H_
