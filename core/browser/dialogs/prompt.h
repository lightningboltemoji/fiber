#ifndef FIBER_BROWSER_DIALOGS_PROMPT_H_
#define FIBER_BROWSER_DIALOGS_PROMPT_H_

#include <memory>
#include <optional>

#include "base/functional/callback.h"
#include "ui/gfx/native_ui_types.h"

@class FiberPromptActionsBridge;
@class FiberPromptContent;
@protocol FiberPrompt;

namespace fiber {

// Something Chrome asks the user, over the veiled page in a Fiber window
// (FiberPromptFactory): adding an extension, say. Destroying it takes the
// prompt down without an answer.
class Prompt {
 public:
  // The button the user pressed, or nullopt if the prompt ended without an
  // answer (its window closed, or another prompt took its place).
  using Callback = base::OnceCallback<void(std::optional<int> button_id)>;

  // Shows `content` in `window`, which comes forward, and runs `callback`
  // once the prompt ends, but not if this is destroyed first. The callback
  // may destroy this. If `window` isn't a Fiber window, the prompt ends at
  // once without an answer (after this returns).
  static std::unique_ptr<Prompt> Show(gfx::NativeWindow window,
                                      FiberPromptContent* content,
                                      Callback callback);

  Prompt(const Prompt&) = delete;
  Prompt& operator=(const Prompt&) = delete;
  ~Prompt();

  // Called by the prompt's actions.
  void OnEnded(std::optional<int> button_id);

 private:
  explicit Prompt(Callback callback);

  Callback callback_;
  FiberPromptActionsBridge* __strong actions_;
  id<FiberPrompt> __strong ui_;
};

}  // namespace fiber

#endif  // FIBER_BROWSER_DIALOGS_PROMPT_H_
