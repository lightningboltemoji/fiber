#include "fiber/browser/sessions/tab_extra_data.h"

#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/sessions/session_service.h"
#include "chrome/browser/sessions/session_service_factory.h"
#include "components/sessions/content/session_tab_helper.h"
#include "content/public/browser/web_contents.h"
#include "fiber/browser/hooks/tab_extra_data.h"
#include "fiber/browser/peek/tab_peek.h"
#include "fiber/browser/pins/pinned_tab_data.h"

namespace fiber {

void SaveTabExtraData(content::WebContents* contents,
                      const char* key,
                      const std::string& value) {
  SessionService* session = SessionServiceFactory::GetForProfile(
      Profile::FromBrowserContext(contents->GetBrowserContext()));
  const SessionID window_id =
      sessions::SessionTabHelper::IdForWindowContainingTab(contents);
  const SessionID tab_id = sessions::SessionTabHelper::IdForTab(contents);
  if (session && window_id.is_valid() && tab_id.is_valid()) {
    session->AddTabExtraData(window_id, tab_id, key, value);
  }
}

std::map<std::string, std::string> TabExtraData(
    content::WebContents* contents) {
  std::map<std::string, std::string> data;
  AddPinExtraData(contents, data);
  AddPeekExtraData(contents, data);
  return data;
}

void RestoreTabExtraData(
    content::WebContents* contents,
    const std::map<std::string, std::string>& extra_data) {
  RestorePinExtraData(contents, extra_data);
  RestorePeekExtraData(contents, extra_data);
}

}  // namespace fiber
