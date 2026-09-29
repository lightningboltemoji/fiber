#ifndef FIBER_BROWSER_DIALOGS_PROMPT_H_
#define FIBER_BROWSER_DIALOGS_PROMPT_H_

#include <memory>
#include <optional>
#include <string>
#include <vector>

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

  // Shows `content` in `window`, bringing it forward. Runs `callback`, which
  // may destroy this, when the prompt ends, unless this is destroyed first.
  // Outside a Fiber window, it ends without an answer after this returns.
  static std::unique_ptr<Prompt> Show(gfx::NativeWindow window,
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

  Callback callback_;
  FiberPromptActionsBridge* __strong actions_;
  id<FiberPrompt> __strong ui_;
};

}  // namespace fiber

#endif  // FIBER_BROWSER_DIALOGS_PROMPT_H_
