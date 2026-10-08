#include "fiber/browser/downloads/downloads_wait.h"

#import <AppKit/AppKit.h>

#include <algorithm>
#include <utility>

#import "FiberBridge/FiberDownloadsWait.h"
#include "base/functional/bind.h"
#include "base/memory/raw_ptr.h"
#include "base/strings/sys_string_conversions.h"
#include "base/task/sequenced_task_runner.h"
#include "base/time/time.h"
#include "chrome/browser/profiles/profile.h"
#include "components/download/public/common/download_item.h"
#include "content/public/browser/download_manager.h"
#include "fiber/browser/downloads/download_state.h"

// Forwards what the user does to its DownloadsWait.
@interface FiberDownloadsWaitActionsBridge
    : NSObject <FiberDownloadsWaitActions>
- (instancetype)initWithOwner:(fiber::DownloadsWait*)owner;
- (void)detachOwner;
@end

@implementation FiberDownloadsWaitActionsBridge {
  raw_ptr<fiber::DownloadsWait> _owner;
}

- (instancetype)initWithOwner:(fiber::DownloadsWait*)owner {
  if ((self = [super init])) {
    _owner = owner;
  }
  return self;
}

- (void)detachOwner {
  _owner = nullptr;
}

- (void)cancelDownloadWithID:(NSString*)downloadID {
  if (_owner) {
    _owner->CancelDownload(base::SysNSStringToUTF8(downloadID));
  }
}

- (void)resumeDownloadWithID:(NSString*)downloadID {
  if (_owner) {
    _owner->ResumeDownload(base::SysNSStringToUTF8(downloadID));
  }
}

- (void)proceedNow {
  if (_owner) {
    _owner->ProceedNow();
  }
}

- (void)stopWaiting {
  if (_owner) {
    _owner->StopWaiting();
  }
}

@end

namespace fiber {

namespace {

// How long updates gather before the UI gets them: a download reports each
// chunk it writes.
constexpr base::TimeDelta kUpdateDelay = base::Milliseconds(250);

// Whether `item` holds up shutdown, as
// content::DownloadManager::BlockingShutdownCount() counts them.
bool IsBlocking(const download::DownloadItem& item) {
  return !item.IsTransient() &&
         item.GetState() == download::DownloadItem::IN_PROGRESS &&
         !item.IsDangerous() && !item.IsInsecure();
}

}  // namespace

// static
base::WeakPtr<DownloadsWait> DownloadsWait::Start(
    Reason reason,
    const std::vector<Profile*>& profiles,
    gfx::NativeWindow window,
    base::OnceCallback<void(bool)> done) {
  auto* wait = new DownloadsWait(profiles, std::move(done));
  base::WeakPtr<DownloadsWait> weak_wait = wait->weak_factory_.GetWeakPtr();
  wait->ui_ = [FiberDownloadsWaitFactory
      waitWithReason:reason == Reason::kQuit
                         ? FiberDownloadsWaitReasonQuit
                         : FiberDownloadsWaitReasonCloseWindow
              window:window.GetNativeNSWindow()
             actions:wait->actions_];
  // Finishing now, with nothing to wait for, would run `done` inside the
  // caller.
  if (wait->BlockingDownloads().empty()) {
    wait->ScheduleUpdate();
  } else {
    wait->Update();
  }
  return weak_wait;
}

DownloadsWait::DownloadsWait(const std::vector<Profile*>& profiles,
                             base::OnceCallback<void(bool)> done)
    : done_(std::move(done)),
      actions_([[FiberDownloadsWaitActionsBridge alloc] initWithOwner:this]) {
  for (Profile* profile : profiles) {
    notifiers_.push_back(std::make_unique<download::AllDownloadItemNotifier>(
        profile->GetDownloadManager(), this));
  }
}

DownloadsWait::~DownloadsWait() {
  [actions_ detachOwner];
  [ui_ close];
}

void DownloadsWait::CancelDownload(const std::string& guid) {
  if (download::DownloadItem* item = FindDownload(guid)) {
    item->Cancel(/*user_cancel=*/true);
  }
}

void DownloadsWait::ResumeDownload(const std::string& guid) {
  if (download::DownloadItem* item = FindDownload(guid)) {
    item->Resume(/*user_resume=*/true);
  }
}

void DownloadsWait::ProceedNow() {
  for (download::DownloadItem* item : BlockingDownloads()) {
    item->Cancel(/*user_cancel=*/true);
  }
  Finish(/*proceed=*/true);
}

void DownloadsWait::StopWaiting() {
  Finish(/*proceed=*/false);
}

void DownloadsWait::Close() {
  Finish(/*proceed=*/false);
}

void DownloadsWait::OnDownloadCreated(content::DownloadManager* manager,
                                      download::DownloadItem* item) {
  ScheduleUpdate();
}

void DownloadsWait::OnDownloadUpdated(content::DownloadManager* manager,
                                      download::DownloadItem* item) {
  ScheduleUpdate();
}

void DownloadsWait::OnDownloadRemoved(content::DownloadManager* manager,
                                      download::DownloadItem* item) {
  ScheduleUpdate();
}

void DownloadsWait::OnDownloadDestroyed(content::DownloadManager* manager,
                                        download::DownloadItem* item) {
  ScheduleUpdate();
}

std::vector<download::DownloadItem*> DownloadsWait::BlockingDownloads() const {
  std::vector<download::DownloadItem*> blocking;
  for (const auto& notifier : notifiers_) {
    content::DownloadManager* manager = notifier->GetManager();
    if (!manager) {
      continue;
    }
    content::DownloadManager::DownloadVector items;
    manager->GetAllDownloads(&items);
    for (download::DownloadItem* item : items) {
      if (IsBlocking(*item)) {
        blocking.push_back(item);
      }
    }
  }
  std::ranges::stable_sort(blocking, {}, [](download::DownloadItem* item) {
    return item->GetStartTime();
  });
  return blocking;
}

download::DownloadItem* DownloadsWait::FindDownload(
    const std::string& guid) const {
  for (const auto& notifier : notifiers_) {
    if (content::DownloadManager* manager = notifier->GetManager()) {
      if (download::DownloadItem* item = manager->GetDownloadByGuid(guid)) {
        return item;
      }
    }
  }
  return nullptr;
}

void DownloadsWait::ScheduleUpdate() {
  if (update_scheduled_) {
    return;
  }
  update_scheduled_ = true;
  base::SequencedTaskRunner::GetCurrentDefault()->PostDelayedTask(
      FROM_HERE,
      base::BindOnce(&DownloadsWait::Update, weak_factory_.GetWeakPtr()),
      kUpdateDelay);
}

void DownloadsWait::Update() {
  update_scheduled_ = false;
  std::vector<download::DownloadItem*> downloads = BlockingDownloads();
  if (downloads.empty()) {
    Finish(/*proceed=*/true);
    return;
  }
  NSMutableArray<FiberDownloadState*>* states = [NSMutableArray array];
  for (download::DownloadItem* item : downloads) {
    [states addObject:DownloadStateFor(item)];
  }
  [ui_ setDownloads:states];
}

void DownloadsWait::Finish(bool proceed) {
  base::OnceCallback<void(bool)> done = std::move(done_);
  delete this;
  std::move(done).Run(proceed);
}

}  // namespace fiber
