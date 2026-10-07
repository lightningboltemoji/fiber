#ifndef FIBER_BROWSER_DIALOGS_TAB_PROMPT_H_
#define FIBER_BROWSER_DIALOGS_TAB_PROMPT_H_

#include <memory>

#include "content/public/browser/weak_document_ptr.h"
#include "content/public/browser/web_contents_observer.h"
#include "fiber/browser/dialogs/prompt.h"

@class FiberPromptContent;

namespace fiber {

// A Prompt over a tab's page (Prompt::ShowForTab()). Like Chrome's tab-modal
// dialogs, it ends without an answer if the tab closes or goes to another
// site.
class TabPrompt : public content::WebContentsObserver {
 public:
  // Runs `callback`, which may destroy this, when the prompt ends, unless this
  // is destroyed first. Outside a Fiber window, it ends without an answer
  // after this returns.
  static std::unique_ptr<TabPrompt> Show(content::WebContents* web_contents,
                                         FiberPromptContent* content,
                                         Prompt::Callback callback);

  TabPrompt(const TabPrompt&) = delete;
  TabPrompt& operator=(const TabPrompt&) = delete;
  ~TabPrompt() override;

  const Prompt& prompt() const { return *prompt_; }

 private:
  TabPrompt(content::WebContents* web_contents, Prompt::Callback callback);

  // content::WebContentsObserver:
  void DidFinishNavigation(
      content::NavigationHandle* navigation_handle) override;
  void WebContentsDestroyed() override;

  // May destroy this.
  void OnEnded(std::optional<int> button_id);
  // Takes the prompt down, and ends it without an answer. May destroy this.
  void EndUnanswered();

  Prompt::Callback callback_;
  // The page it was shown over.
  content::WeakDocumentPtr document_;
  std::unique_ptr<Prompt> prompt_;
};

}  // namespace fiber

#endif  // FIBER_BROWSER_DIALOGS_TAB_PROMPT_H_
