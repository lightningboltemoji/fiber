#ifndef FIBER_BROWSER_HOOKS_DOWNLOAD_UI_H_
#define FIBER_BROWSER_HOOKS_DOWNLOAD_UI_H_

#include <memory>

#include "chrome/browser/download/download_ui_controller.h"

class Profile;

namespace fiber {

// For DownloadUIController on the Mac, in place of the delegate that feeds
// Chrome's download bubble: Fiber's windows list downloads themselves (see
// FiberDownloads).
std::unique_ptr<DownloadUIController::Delegate>
CreateDownloadUIControllerDelegate(Profile* profile);

}  // namespace fiber

#endif  // FIBER_BROWSER_HOOKS_DOWNLOAD_UI_H_
