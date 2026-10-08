#include "fiber/browser/downloads/download_state.h"

#import <AppKit/AppKit.h>

#import "FiberBridge/FiberDownloads.h"
#include "base/apple/foundation_util.h"
#include "base/notreached.h"
#include "base/strings/sys_string_conversions.h"
#include "base/time/time.h"
#include "chrome/browser/download/download_item_model.h"
#include "chrome/browser/download/offline_item_utils.h"
#include "components/download/public/common/download_danger_type.h"
#include "components/download/public/common/download_item.h"
#include "components/offline_items_collection/core/fail_state.h"

namespace fiber {

namespace {

FiberDownloadStatus StatusFor(const DownloadItemModel& model) {
  switch (model.GetState()) {
    case download::DownloadItem::IN_PROGRESS:
      return model.IsDangerous() || model.IsInsecure()
                 ? FiberDownloadStatusNeedsReview
                 : FiberDownloadStatusInProgress;
    case download::DownloadItem::COMPLETE:
      return FiberDownloadStatusComplete;
    case download::DownloadItem::INTERRUPTED:
      return model.GetLastFailState() ==
                     offline_items_collection::FailState::USER_CANCELED
                 ? FiberDownloadStatusCancelled
                 : FiberDownloadStatusFailed;
    case download::DownloadItem::CANCELLED:
      return FiberDownloadStatusCancelled;
    case download::DownloadItem::MAX_DOWNLOAD_STATE:
      break;
  }
  NOTREACHED();
}

}  // namespace

FiberDownloadState* DownloadStateFor(download::DownloadItem* item) {
  DownloadItemModel model(item);
  const FiberDownloadStatus status = StatusFor(model);
  const std::u16string file_name =
      model.GetFileNameToReportUser().LossyDisplayName();
  const base::FilePath path = model.GetTargetFilePath();
  size_t offset;
  const std::u16string warning =
      status == FiberDownloadStatusNeedsReview
          ? model.GetWarningText(file_name, &offset)
          : std::u16string();
  base::TimeDelta remaining;
  const bool has_remaining = model.TimeRemaining(&remaining);
  const int percent = model.PercentComplete();
  return [[FiberDownloadState alloc]
      initWithDownloadID:base::SysUTF8ToNSString(item->GetGuid())
                fileName:base::SysUTF16ToNSString(file_name)
                filePath:path.empty() ? @""
                                      : base::apple::FilePathToNSString(path)
                  status:status
              statusText:base::SysUTF16ToNSString(model.GetStatusText())
             warningText:base::SysUTF16ToNSString(warning)
                  origin:base::SysUTF16ToNSString(
                             model.GetDownloadDomainForDisplay())
           receivedBytes:model.GetCompletedBytes()
              totalBytes:model.GetTotalBytes()
                progress:percent < 0 ? -1 : percent / 100.0
           timeRemaining:has_remaining ? remaining.InSecondsF() : -1
                  paused:model.IsPaused()
               canResume:model.CanResume()
                canRetry:DownloadStateCanRetry(*item)
                 canKeep:DownloadStateCanKeep(*item)
             fileMissing:model.GetFileExternallyRemoved()];
}

bool DownloadStateCanRetry(const download::DownloadItem& item) {
  using offline_items_collection::FailState;
  switch (item.GetState()) {
    case download::DownloadItem::CANCELLED:
      return true;
    case download::DownloadItem::INTERRUPTED:
      break;
    default:
      return false;
  }
  switch (item.GetDangerType()) {
    case download::DOWNLOAD_DANGER_TYPE_BLOCKED_PASSWORD_PROTECTED:
    case download::DOWNLOAD_DANGER_TYPE_BLOCKED_TOO_LARGE:
    case download::DOWNLOAD_DANGER_TYPE_FORCE_SAVE_TO_GDRIVE:
    case download::DOWNLOAD_DANGER_TYPE_FORCE_SAVE_TO_ONEDRIVE:
    case download::DOWNLOAD_DANGER_TYPE_SENSITIVE_CONTENT_BLOCK:
      return false;
    default:
      break;
  }
  switch (OfflineItemUtils::ConvertDownloadInterruptReasonToFailState(
      item.GetLastReason())) {
    case FailState::USER_CANCELED:
    case FailState::NETWORK_INVALID_REQUEST:
    case FailState::NETWORK_FAILED:
    case FailState::NETWORK_TIMEOUT:
    case FailState::NETWORK_DISCONNECTED:
    case FailState::NETWORK_SERVER_DOWN:
    case FailState::FILE_TRANSIENT_ERROR:
    case FailState::USER_SHUTDOWN:
    case FailState::CRASH:
    case FailState::SERVER_CONTENT_LENGTH_MISMATCH:
    case FailState::SERVER_NO_RANGE:
    case FailState::SERVER_CROSS_ORIGIN_REDIRECT:
    case FailState::FILE_FAILED:
    case FailState::FILE_HASH_MISMATCH:
    case FailState::SERVER_FAILED:
    case FailState::SERVER_CERT_PROBLEM:
    case FailState::SERVER_UNREACHABLE:
    case FailState::FILE_TOO_SHORT:
      return true;
    default:
      return false;
  }
}

bool DownloadStateCanKeep(const download::DownloadItem& item) {
  switch (item.GetDangerType()) {
    case download::DOWNLOAD_DANGER_TYPE_DANGEROUS_FILE:
    case download::DOWNLOAD_DANGER_TYPE_UNCOMMON_CONTENT:
    case download::DOWNLOAD_DANGER_TYPE_SENSITIVE_CONTENT_WARNING:
      return true;
    default:
      return !item.IsDangerous() && item.IsInsecure();
  }
}

}  // namespace fiber
