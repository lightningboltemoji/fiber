#include "fiber/browser/hooks/download_ui.h"

#include "chrome/browser/profiles/profile.h"
#include "chrome/common/pref_names.h"
#include "components/download/public/common/desktop/desktop_auto_resumption_handler.h"
#include "components/download/public/common/download_features.h"
#include "components/download/public/common/download_item.h"
#include "components/prefs/pref_service.h"

namespace fiber {

namespace {

// Does what Chrome's download bubble delegate does besides feed the bubble.
class FiberDownloadUIDelegate : public DownloadUIController::Delegate {
 public:
  explicit FiberDownloadUIDelegate(Profile* profile) {
    // Incognito always asks where to save, whatever the setting.
    if (profile->IsOffTheRecord()) {
      profile->GetPrefs()->SetBoolean(prefs::kPromptForDownload, true);
    }
  }

  // DownloadUIController::Delegate:
  void OnNewDownloadReady(download::DownloadItem* item) override {
    // Now that the user can see it, it resumes by itself after a network
    // error.
    if (download::features::IsBackoffInDownloadingEnabled()) {
      auto* handler = download::DesktopAutoResumptionHandler::Get();
      item->RemoveObserver(handler);
      item->AddObserver(handler);
    }
  }
};

}  // namespace

std::unique_ptr<DownloadUIController::Delegate>
CreateDownloadUIControllerDelegate(Profile* profile) {
  return std::make_unique<FiberDownloadUIDelegate>(profile);
}

}  // namespace fiber
