#include "fiber/browser/dialogs/tab_prompt.h"

#include <utility>

#include "base/functional/bind.h"
#include "base/memory/ptr_util.h"
#include "content/public/browser/navigation_handle.h"
#include "content/public/browser/web_contents.h"
#include "fiber/browser/window/fiber_browser_window.h"
#include "net/base/registry_controlled_domains/registry_controlled_domain.h"

namespace fiber {

// static
std::unique_ptr<TabPrompt> TabPrompt::Show(content::WebContents* web_contents,
                                           FiberPromptContent* content,
                                           Prompt::Callback callback) {
  auto tab_prompt =
      base::WrapUnique(new TabPrompt(web_contents, std::move(callback)));
  FiberBrowserWindow* window =
      FiberBrowserWindow::FromWebContents(web_contents);
  tab_prompt->prompt_ = Prompt::Show(
      window ? window->GetNativeWindow() : gfx::NativeWindow(), content,
      base::BindOnce(&TabPrompt::OnEnded,
                     base::Unretained(tab_prompt.get())));
  return tab_prompt;
}

TabPrompt::TabPrompt(content::WebContents* web_contents,
                     Prompt::Callback callback)
    : content::WebContentsObserver(web_contents),
      callback_(std::move(callback)) {}

TabPrompt::~TabPrompt() = default;

void TabPrompt::DidFinishNavigation(
    content::NavigationHandle* navigation_handle) {
  // As web_modal::WebContentsModalDialogManager closes Chrome's.
  if (!navigation_handle->IsInPrimaryMainFrame() ||
      !navigation_handle->HasCommitted() ||
      net::registry_controlled_domains::SameDomainOrHost(
          navigation_handle->GetPreviousPrimaryMainFrameURL(),
          navigation_handle->GetURL(),
          net::registry_controlled_domains::INCLUDE_PRIVATE_REGISTRIES)) {
    return;
  }
  EndUnanswered();
}

void TabPrompt::WebContentsDestroyed() {
  EndUnanswered();
}

void TabPrompt::OnEnded(std::optional<int> button_id) {
  if (callback_) {
    std::move(callback_).Run(button_id);
  }
}

void TabPrompt::EndUnanswered() {
  Observe(nullptr);
  prompt_.reset();
  OnEnded(std::nullopt);
}

}  // namespace fiber
