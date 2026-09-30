#include "fiber/browser/new_tab/new_tab_page_ui.h"

#include <string>

#include "base/functional/bind.h"
#include "base/memory/ref_counted_memory.h"
#include "base/strings/escape.h"
#include "base/strings/strcat.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/common/webui_url_constants.h"
#include "components/strings/grit/components_strings.h"
#include "content/public/browser/web_contents.h"
#include "content/public/browser/web_ui.h"
#include "content/public/browser/web_ui_data_source.h"
#include "content/public/common/url_constants.h"
#include "ui/base/l10n/l10n_util.h"

namespace fiber {

namespace {

// An empty page in the window's background color (NSColor's
// windowBackgroundColor on macOS 26), light and dark. An Incognito window is
// always dark (BrowserWindowController.swift).
std::string PageHTML(bool incognito) {
  constexpr char kLightAndDark[] =
      "html { background: #ffffff; }"
      "@media (prefers-color-scheme: dark) { html { background: #1e1e1e; } }";
  constexpr char kDark[] = "html { background: #1e1e1e; }";
  return base::StrCat(
      {"<!doctype html><html><head><meta charset=\"utf-8\">"
       "<meta name=\"color-scheme\" content=\"",
       incognito ? "dark" : "light dark", "\"><title>",
       base::EscapeForHTML(l10n_util::GetStringUTF8(IDS_NEW_TAB_TITLE)),
       "</title><style>", incognito ? kDark : kLightAndDark,
       "</style></head></html>"});
}

}  // namespace

NewTabPageUIConfig::NewTabPageUIConfig()
    : DefaultWebUIConfig(content::kChromeUIScheme,
                         chrome::kChromeUINewTabHost) {}

NewTabPageUI::NewTabPageUI(content::WebUI* web_ui)
    : content::WebUIController(web_ui) {
  content::WebUIDataSource* source = content::WebUIDataSource::CreateAndAdd(
      web_ui->GetWebContents()->GetBrowserContext(),
      chrome::kChromeUINewTabHost);
  source->SetRequestFilter(
      base::BindRepeating([](const std::string& path) { return true; }),
      base::BindRepeating(
          [](bool incognito, const std::string& path,
             content::WebUIDataSource::GotDataCallback callback) {
            std::move(callback).Run(
                base::MakeRefCounted<base::RefCountedString>(
                    PageHTML(incognito)));
          },
          Profile::FromWebUI(web_ui)->IsIncognitoProfile()));
}

NewTabPageUI::~NewTabPageUI() = default;

}  // namespace fiber
