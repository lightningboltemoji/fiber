#include "fiber/browser/pins/pinned_tab_data.h"

#include <utility>

#include "content/public/browser/web_contents.h"
#include "content/public/browser/web_contents_user_data.h"
#include "fiber/browser/sessions/tab_extra_data.h"

namespace fiber {

namespace {

constexpr char kPinIDKey[] = "fiber_pin_id";
constexpr char kBesidePinKey[] = "fiber_beside_pin";

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

class BesidePinData : public content::WebContentsUserData<BesidePinData> {
 public:
  ~BesidePinData() override = default;

 private:
  friend WebContentsUserData;

  explicit BesidePinData(content::WebContents* contents)
      : WebContentsUserData(*contents) {}

  WEB_CONTENTS_USER_DATA_KEY_DECL();
};

WEB_CONTENTS_USER_DATA_KEY_IMPL(BesidePinData);

void SetPinID(content::WebContents* contents, std::string_view pin_id) {
  contents->RemoveUserData(PinnedTabData::UserDataKey());
  if (!pin_id.empty()) {
    PinnedTabData::CreateForWebContents(contents, std::string(pin_id));
  }
}

void SetBeside(content::WebContents* contents, bool beside) {
  if (beside) {
    BesidePinData::CreateForWebContents(contents);
  } else {
    contents->RemoveUserData(BesidePinData::UserDataKey());
  }
}

}  // namespace

std::string PinIDForTab(content::WebContents* contents) {
  PinnedTabData* data = PinnedTabData::FromWebContents(contents);
  return data ? data->pin_id() : std::string();
}

void SetPinIDForTab(content::WebContents* contents, std::string_view pin_id) {
  SetPinID(contents, pin_id);
  SaveTabExtraData(contents, kPinIDKey, std::string(pin_id));
}

bool IsBesidePin(content::WebContents* contents) {
  return BesidePinData::FromWebContents(contents) != nullptr;
}

void SetBesidePin(content::WebContents* contents, bool beside) {
  if (beside == IsBesidePin(contents)) {
    return;
  }
  SetBeside(contents, beside);
  SaveTabExtraData(contents, kBesidePinKey, beside ? "1" : "");
}

void AddPinExtraData(content::WebContents* contents,
                     std::map<std::string, std::string>& extra_data) {
  if (std::string pin_id = PinIDForTab(contents); !pin_id.empty()) {
    extra_data[kPinIDKey] = std::move(pin_id);
  }
  if (IsBesidePin(contents)) {
    extra_data[kBesidePinKey] = "1";
  }
}

void RestorePinExtraData(
    content::WebContents* contents,
    const std::map<std::string, std::string>& extra_data) {
  auto it = extra_data.find(kPinIDKey);
  if (it != extra_data.end()) {
    SetPinID(contents, it->second);
  }
  it = extra_data.find(kBesidePinKey);
  SetBeside(contents, it != extra_data.end() && it->second == "1");
}

}  // namespace fiber
