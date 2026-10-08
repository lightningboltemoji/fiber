#ifndef FIBER_BROWSER_DOWNLOADS_DOWNLOAD_STATE_H_
#define FIBER_BROWSER_DOWNLOADS_DOWNLOAD_STATE_H_

@class FiberDownloadState;

namespace download {
class DownloadItem;
}

namespace fiber {

// `item` as the UI shows it.
FiberDownloadState* DownloadStateFor(download::DownloadItem* item);

// Whether `item`, failed or cancelled, is worth downloading again: not if it
// was blocked, or would fail the same way. As Chrome's download bubble has it.
bool DownloadStateCanRetry(const download::DownloadItem& item);

// Whether `item`, needing review, may be kept anyway: Chrome's download bubble
// only offers to delete one that's known to be malicious, or awaits a scan.
bool DownloadStateCanKeep(const download::DownloadItem& item);

}  // namespace fiber

#endif  // FIBER_BROWSER_DOWNLOADS_DOWNLOAD_STATE_H_
