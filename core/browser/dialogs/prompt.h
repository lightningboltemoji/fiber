#ifndef FIBER_BROWSER_DIALOGS_PROMPT_H_
#define FIBER_BROWSER_DIALOGS_PROMPT_H_

#include <memory>
#include <optional>
#include <string>
#include <vector>

#include "base/functional/callback.h"
#include "base/memory/weak_ptr.h"
#include "ui/gfx/native_ui_types.h"

@class FiberPromptActionsBridge;
@class FiberPromptContent;
@protocol FiberPrompt;

namespace content {
class WebContents;
}

namespace fiber {

// Something Chrome asks the user in a Fiber window (FiberPromptFactory):
// adding an extension, say. Destroying it takes the prompt down without an
// answer.
class Prompt {
 public:
  // The button the user pressed, or nullopt if the prompt ended without an
  // answer (its tab or window closed, or another prompt took its place).
  using Callback = base::OnceCallback<void(std::optional<int> button_id)>;

  // Shows `content` as `window`'s own, bringing it forward. Runs `callback`,
  // which may destroy this, when the prompt ends, unless this is destroyed
  // first. Outside a Fiber window, it ends unanswered after this returns.
  static std::unique_ptr<Prompt> Show(gfx::NativeWindow window,
                                      FiberPromptContent* content,
                                      Callback callback);
  // Shows `content` over `web_contents`'s page while it's the active tab of
  // its Fiber window. Otherwise as Show().
  static std::unique_ptr<Prompt> ShowForTab(content::WebContents* web_contents,
                                            FiberPromptContent* content,
                                            Callback callback);

  Prompt(const Prompt&) = delete;
  Prompt& operator=(const Prompt&) = delete;
  ~Prompt();

  // The text of `content`'s fields, in order, and whether its checkbox is
  // checked: as they stand, or as they were when the prompt ended.
  std::vector<std::u16string> GetFieldValues() const;
  bool IsCheckboxChecked() const;

  // Called by the prompt's actions.
  void OnEnded(std::optional<int> button_id);

 private:
  explicit Prompt(Callback callback);

  // With nowhere to ask, ends without an answer, after the caller has the
  // prompt.
  void EndUnansweredSoon();

  Callback callback_;
  FiberPromptActionsBridge* __strong actions_;
  id<FiberPrompt> __strong ui_;
  base::WeakPtrFactory<Prompt> weak_factory_{this};
};

}  // namespace fiber

#endif  // FIBER_BROWSER_DIALOGS_PROMPT_H_
