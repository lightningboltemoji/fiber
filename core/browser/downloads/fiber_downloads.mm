#include "fiber/browser/downloads/fiber_downloads.h"

#import <AppKit/AppKit.h>

#include <algorithm>
#include <memory>
#include <utility>

#import "FiberBridge/FiberDownloads.h"
#include "base/functional/bind.h"
#include "base/memory/raw_ptr.h"
#include "base/strings/sys_string_conversions.h"
#include "base/task/sequenced_task_runner.h"
#include "base/time/time.h"
#include "chrome/browser/download/chrome_download_manager_delegate.h"
#include "chrome/browser/download/download_core_service.h"
#include "chrome/browser/download/download_core_service_factory.h"
#include "chrome/browser/download/download_item_model.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#include "chrome/browser/ui/chrome_pages.h"
#include "components/download/public/common/download_item.h"
#include "components/download/public/common/download_source.h"
#include "components/download/public/common/download_url_parameters.h"
#include "content/public/browser/download_manager.h"
#include "fiber/browser/downloads/download_state.h"
#include "net/traffic_annotation/network_traffic_annotation.h"

// Forwards what the user does to its FiberDownloads.
@interface FiberDownloadsActionsBridge : NSObject <FiberDownloadsActions>
- (instancetype)initWithOwner:(fiber::FiberDownloads*)owner;
- (void)detachOwner;
@end

@implementation FiberDownloadsActionsBridge {
  raw_ptr<fiber::FiberDownloads> _owner;
}

- (instancetype)initWithOwner:(fiber::FiberDownloads*)owner {
  if ((self = [super init])) {
    _owner = owner;
  }
  return self;
}

- (void)detachOwner {
  _owner = nullptr;
}

- (void)openDownloadWithID:(NSString*)downloadID {
  if (_owner) {
    _owner->Open(base::SysNSStringToUTF8(downloadID));
  }
}

- (void)showDownloadInFinderWithID:(NSString*)downloadID {
  if (_owner) {
    _owner->ShowInFinder(base::SysNSStringToUTF8(downloadID));
  }
}

- (void)pauseDownloadWithID:(NSString*)downloadID {
  if (_owner) {
    _owner->Pause(base::SysNSStringToUTF8(downloadID));
  }
}

- (void)resumeDownloadWithID:(NSString*)downloadID {
  if (_owner) {
    _owner->Resume(base::SysNSStringToUTF8(downloadID));
  }
}

- (void)cancelDownloadWithID:(NSString*)downloadID {
  if (_owner) {
    _owner->Cancel(base::SysNSStringToUTF8(downloadID));
  }
}

- (void)retryDownloadWithID:(NSString*)downloadID {
  if (_owner) {
    _owner->Retry(base::SysNSStringToUTF8(downloadID));
  }
}

- (void)keepDownloadWithID:(NSString*)downloadID {
  if (_owner) {
    _owner->Keep(base::SysNSStringToUTF8(downloadID));
  }
}

- (void)discardDownloadWithID:(NSString*)downloadID {
  if (_owner) {
    _owner->Discard(base::SysNSStringToUTF8(downloadID));
  }
}

- (void)removeDownloadWithID:(NSString*)downloadID {
  if (_owner) {
    _owner->Remove(base::SysNSStringToUTF8(downloadID));
  }
}

- (void)clearDownloads {
  if (_owner) {
    _owner->Clear();
  }
}

- (void)showAllDownloads {
  if (_owner) {
    _owner->ShowAll();
  }
}

- (void)downloadsDidShow {
  if (_owner) {
    _owner->OnShown();
  }
}

@end

namespace fiber {

namespace {

// How long updates gather before the UI gets them: a download reports each
// chunk it writes.
constexpr base::TimeDelta kUpdateDelay = base::Milliseconds(250);

// How long a download stays listed after it starts, unless it's still going,
// as in Chrome's download bubble.
constexpr base::TimeDelta kRecentAge = base::Days(1);

// As many as Chrome's download bubble lists.
constexpr size_t kMaxListed = 30;

// Downloading, paused, or waiting on review: not yet done with, nor failed.
bool IsActive(const download::DownloadItem& item) {
  return item.GetState() == download::DownloadItem::IN_PROGRESS;
}

bool NeedsReview(const download::DownloadItem& item) {
  return IsActive(item) && (item.IsDangerous() || item.IsInsecure());
}

}  // namespace

FiberDownloads::FiberDownloads(BrowserWindowInterface* browser,
                               id<FiberDownloads> ui)
    : browser_(browser),
      ui_(ui),
      actions_([[FiberDownloadsActionsBridge alloc] initWithOwner:this]) {
  notifier_.emplace(browser->GetProfile()->GetDownloadManager(), this);
  ui.actions = actions_;
  Update();
}

FiberDownloads::~FiberDownloads() {
  [actions_ detachOwner];
}

void FiberDownloads::Open(const std::string& guid) {
  ExecuteCommand(guid, DownloadCommands::OPEN_WHEN_COMPLETE);
}

void FiberDownloads::ShowInFinder(const std::string& guid) {
  ExecuteCommand(guid, DownloadCommands::SHOW_IN_FOLDER);
}

void FiberDownloads::Pause(const std::string& guid) {
  ExecuteCommand(guid, DownloadCommands::PAUSE);
}

void FiberDownloads::Resume(const std::string& guid) {
  ExecuteCommand(guid, DownloadCommands::RESUME);
}

void FiberDownloads::Cancel(const std::string& guid) {
  ExecuteCommand(guid, DownloadCommands::CANCEL);
}

void FiberDownloads::Retry(const std::string& guid) {
  download::DownloadItem* item = FindDownload(guid);
  content::DownloadManager* manager = notifier_->GetManager();
  if (!item || !manager || !DownloadStateCanRetry(*item)) {
    return;
  }
  net::NetworkTrafficAnnotationTag traffic_annotation =
      net::DefineNetworkTrafficAnnotation("fiber_downloads_retry", R"(
        semantics {
          sender: "Fiber's downloads list"
          description:
            "Downloads a file again after its download failed or was "
            "cancelled."
          trigger: "The user retries the download in the tab overlay."
          data: "None"
          destination: WEBSITE
        }
        policy {
          cookies_allowed: YES
          cookies_store: "user"
          setting: "Only sent when the user asks."
          policy_exception_justification: "Not implemented."
        })");
  // From the last URL in the chain, as resuming does, and as the user's own
  // request rather than the page's.
  auto parameters = std::make_unique<download::DownloadUrlParameters>(
      item->GetURL(), traffic_annotation);
  parameters->set_content_initiated(false);
  parameters->set_download_source(download::DownloadSource::RETRY_FROM_BUBBLE);
  manager->DownloadUrl(std::move(parameters));
}

void FiberDownloads::Keep(const std::string& guid) {
  download::DownloadItem* item = FindDownload(guid);
  if (item && NeedsReview(*item) && DownloadStateCanKeep(*item)) {
    ExecuteCommand(guid, DownloadCommands::KEEP);
  }
}

void FiberDownloads::Discard(const std::string& guid) {
  download::DownloadItem* item = FindDownload(guid);
  if (item && NeedsReview(*item)) {
    ExecuteCommand(guid, DownloadCommands::DISCARD);
  }
}

void FiberDownloads::Remove(const std::string& guid) {
  download::DownloadItem* item = FindDownload(guid);
  if (item && !IsActive(*item)) {
    item->Remove();
  }
}

void FiberDownloads::Clear() {
  std::vector<std::string> inactive;
  for (download::DownloadItem* item : ListedDownloads()) {
    if (!IsActive(*item)) {
      inactive.push_back(item->GetGuid());
    }
  }
  // Each removal can destroy the item, so look each up again.
  for (const std::string& guid : inactive) {
    Remove(guid);
  }
}

void FiberDownloads::ShowAll() {
  chrome::ShowDownloads(browser_);
}

void FiberDownloads::OnShown() {
  DownloadCoreService* service =
      DownloadCoreServiceFactory::GetForBrowserContext(browser_->GetProfile());
  ChromeDownloadManagerDelegate* delegate =
      service ? service->GetDownloadManagerDelegate() : nullptr;
  for (download::DownloadItem* item : ListedDownloads()) {
    DownloadItemModel model(item);
    // As Chrome's download bubble does once it shows one: the warning goes
    // after a while, and the download is cancelled after a while longer.
    if (model.IsEphemeralWarning() &&
        !model.GetEphemeralWarningUiShownTime().has_value()) {
      model.SetEphemeralWarningUiShownTime(base::Time::Now());
      if (delegate) {
        delegate->ScheduleCancelForEphemeralWarning(item->GetGuid());
      }
    }
  }
}

void FiberDownloads::OnManagerInitialized(content::DownloadManager* manager) {
  ScheduleUpdate();
}

void FiberDownloads::OnDownloadCreated(content::DownloadManager* manager,
                                       download::DownloadItem* item) {
  ScheduleUpdate();
}

void FiberDownloads::OnDownloadUpdated(content::DownloadManager* manager,
                                       download::DownloadItem* item) {
  ScheduleUpdate();
}

void FiberDownloads::OnDownloadRemoved(content::DownloadManager* manager,
                                       download::DownloadItem* item) {
  ScheduleUpdate();
}

void FiberDownloads::OnDownloadDestroyed(content::DownloadManager* manager,
                                         download::DownloadItem* item) {
  ScheduleUpdate();
}

download::DownloadItem* FiberDownloads::FindDownload(
    const std::string& guid) const {
  content::DownloadManager* manager = notifier_->GetManager();
  return manager ? manager->GetDownloadByGuid(guid) : nullptr;
}

void FiberDownloads::ExecuteCommand(const std::string& guid,
                                    DownloadCommands::Command command) {
  download::DownloadItem* item = FindDownload(guid);
  if (!item) {
    return;
  }
  DownloadItemModel model(item);
  DownloadCommands commands(model.GetWeakPtr());
  if (commands.IsCommandEnabled(command)) {
    commands.ExecuteCommand(command);
  }
}

std::vector<download::DownloadItem*> FiberDownloads::ListedDownloads() const {
  std::vector<download::DownloadItem*> listed;
  content::DownloadManager* manager = notifier_->GetManager();
  DownloadCoreService* service =
      DownloadCoreServiceFactory::GetForBrowserContext(browser_->GetProfile());
  if (!manager || (service && !service->IsDownloadUiEnabled())) {
    return listed;
  }
  content::DownloadManager::DownloadVector items;
  manager->GetAllDownloads(&items);
  const base::Time cutoff = base::Time::Now() - kRecentAge;
  for (download::DownloadItem* item : items) {
    if ((IsActive(*item) || item->GetStartTime() > cutoff) &&
        DownloadItemModel(item).ShouldShowInBubble()) {
      listed.push_back(item);
    }
  }
  std::ranges::sort(listed, [](download::DownloadItem* a,
                               download::DownloadItem* b) {
    if (IsActive(*a) != IsActive(*b)) {
      return IsActive(*a);
    }
    return a->GetStartTime() > b->GetStartTime();
  });
  if (listed.size() > kMaxListed) {
    listed.resize(kMaxListed);
  }
  return listed;
}

void FiberDownloads::ScheduleUpdate() {
  if (update_scheduled_) {
    return;
  }
  update_scheduled_ = true;
  base::SequencedTaskRunner::GetCurrentDefault()->PostDelayedTask(
      FROM_HERE,
      base::BindOnce(&FiberDownloads::Update, weak_factory_.GetWeakPtr()),
      kUpdateDelay);
}

void FiberDownloads::Update() {
  update_scheduled_ = false;
  NSMutableArray<FiberDownloadState*>* states = [NSMutableArray array];
  for (download::DownloadItem* item : ListedDownloads()) {
    [states addObject:DownloadStateFor(item)];
  }
  [ui_ setDownloads:states];
}

}  // namespace fiber
