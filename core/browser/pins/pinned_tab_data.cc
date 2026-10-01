#include "fiber/browser/pins/pinned_tab_data.h"

#include <utility>

#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/sessions/session_service.h"
#include "chrome/browser/sessions/session_service_factory.h"
#include "components/sessions/content/session_tab_helper.h"
#include "content/public/browser/web_contents.h"
#include "content/public/browser/web_contents_user_data.h"
#include "fiber/browser/hooks/tab_extra_data.h"

namespace fiber {

namespace {

constexpr char kPinIDKey[] = "fiber_pin_id";

class PinnedTabData : public content::WebContentsUserData<PinnedTabData> {
 public:
  ~PinnedTabData() override = default;

  const std::string& pin_id() const { return pin_id_; }

 private:
  friend WebContentsUserData;

  PinnedTabData(content::WebContents* contents, std::string pin_id)
      : WebContentsUserData(*contents), pin_id_(std::move(pin_id)) {}

  const std::string pin_id_;

  WEB_CONTENTS_USER_DATA_KEY_DECL();
};

WEB_CONTENTS_USER_DATA_KEY_IMPL(PinnedTabData);

void SetPinID(content::WebContents* contents, std::string_view pin_id) {
  contents->RemoveUserData(PinnedTabData::UserDataKey());
  if (!pin_id.empty()) {
    PinnedTabData::CreateForWebContents(contents, std::string(pin_id));
  }
}

}  // namespace

std::string PinIDForTab(content::WebContents* contents) {
  PinnedTabData* data = PinnedTabData::FromWebContents(contents);
  return data ? data->pin_id() : std::string();
}

void SetPinIDForTab(content::WebContents* contents, std::string_view pin_id) {
  SetPinID(contents, pin_id);
  // Until the tab is in a window, its session doesn't know it.
  SessionService* session = SessionServiceFactory::GetForProfile(
      Profile::FromBrowserContext(contents->GetBrowserContext()));
  const SessionID window_id =
      sessions::SessionTabHelper::IdForWindowContainingTab(contents);
  const SessionID tab_id = sessions::SessionTabHelper::IdForTab(contents);
  if (session && window_id.is_valid() && tab_id.is_valid()) {
    session->AddTabExtraData(window_id, tab_id, kPinIDKey, std::string(pin_id));
  }
}

std::map<std::string, std::string> TabExtraData(
    content::WebContents* contents) {
  std::string pin_id = PinIDForTab(contents);
  if (pin_id.empty()) {
    return {};
  }
  return {{kPinIDKey, std::move(pin_id)}};
}

void RestoreTabExtraData(
    content::WebContents* contents,
    const std::map<std::string, std::string>& extra_data) {
  auto it = extra_data.find(kPinIDKey);
  if (it != extra_data.end()) {
    SetPinID(contents, it->second);
  }
}

}  // namespace fiber
