#include "fiber/browser/window/key_passthrough.h"

#include "content/public/browser/page.h"
#include "content/public/browser/render_frame_host.h"
#include "content/public/browser/web_contents.h"
#include "content/public/browser/web_contents_observer.h"
#include "content/public/browser/web_contents_user_data.h"
#include "fiber/browser/window/fiber_browser_window.h"
#include "net/base/schemeful_site.h"
#include "url/gurl.h"

namespace fiber {

namespace {

class KeyPassthrough : public content::WebContentsUserData<KeyPassthrough>,
                       public content::WebContentsObserver {
 public:
  ~KeyPassthrough() override = default;

  // content::WebContentsObserver:
  void PrimaryPageChanged(content::Page& page) override {
    if (!net::SchemefulSite::IsSameSite(
            url_, page.GetMainDocument().GetLastCommittedURL())) {
      EndKeyPassthrough(web_contents());
    }
  }

 private:
  friend WebContentsUserData;

  explicit KeyPassthrough(content::WebContents* contents)
      : WebContentsUserData(*contents),
        WebContentsObserver(contents),
        url_(contents->GetLastCommittedURL()) {}

  // Where the tab was when it started.
  const GURL url_;

  WEB_CONTENTS_USER_DATA_KEY_DECL();
};

WEB_CONTENTS_USER_DATA_KEY_IMPL(KeyPassthrough);

void UpdateWindow(content::WebContents* contents) {
  if (FiberBrowserWindow* window =
          FiberBrowserWindow::FromWebContents(contents)) {
    window->UpdatePageState();
  }
}

}  // namespace

bool HasKeyPassthrough(content::WebContents* contents) {
  return KeyPassthrough::FromWebContents(contents) != nullptr;
}

void StartKeyPassthrough(content::WebContents* contents) {
  if (!HasKeyPassthrough(contents)) {
    KeyPassthrough::CreateForWebContents(contents);
    UpdateWindow(contents);
  }
}

void EndKeyPassthrough(content::WebContents* contents) {
  if (HasKeyPassthrough(contents)) {
    contents->RemoveUserData(KeyPassthrough::UserDataKey());
    UpdateWindow(contents);
  }
}

}  // namespace fiber
