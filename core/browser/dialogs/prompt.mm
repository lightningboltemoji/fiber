#include "fiber/browser/dialogs/prompt.h"

#import <AppKit/AppKit.h>

#include <utility>

#import "FiberBridge/FiberPrompt.h"
#include "base/functional/bind.h"
#include "base/location.h"
#include "base/memory/ptr_util.h"
#include "base/memory/raw_ptr.h"
#include "base/strings/sys_string_conversions.h"
#include "base/task/sequenced_task_runner.h"
#include "components/tabs/public/tab_interface.h"
#include "fiber/browser/window/fiber_browser_window.h"

// Forwards how the prompt ended to its fiber::Prompt.
@interface FiberPromptActionsBridge : NSObject <FiberPromptActions>
- (instancetype)initWithOwner:(fiber::Prompt*)owner;
- (void)detachOwner;
@end

@implementation FiberPromptActionsBridge {
  raw_ptr<fiber::Prompt> _owner;
}

- (instancetype)initWithOwner:(fiber::Prompt*)owner {
  if ((self = [super init])) {
    _owner = owner;
  }
  return self;
}

- (void)detachOwner {
  _owner = nullptr;
}

- (void)promptDidPressButtonWithID:(NSInteger)buttonID {
  if (_owner) {
    _owner->OnEnded(static_cast<int>(buttonID));
  }
}

- (void)promptDidDismiss {
  if (_owner) {
    _owner->OnEnded(std::nullopt);
  }
}

@end

namespace fiber {

// static
std::unique_ptr<Prompt> Prompt::Show(gfx::NativeWindow window,
                                     FiberPromptContent* content,
                                     Callback callback) {
  auto prompt = base::WrapUnique(new Prompt(std::move(callback)));
  NSWindow* ns_window = window.GetNativeNSWindow();
  if (!ns_window) {
    prompt->EndUnansweredSoon();
    return prompt;
  }
  prompt->ui_ = [FiberPromptFactory promptWithContent:content
                                               window:ns_window
                                              actions:prompt->actions_];
  return prompt;
}

// static
std::unique_ptr<Prompt> Prompt::ShowForTab(content::WebContents* web_contents,
                                           FiberPromptContent* content,
                                           Callback callback) {
  auto prompt = base::WrapUnique(new Prompt(std::move(callback)));
  FiberBrowserWindow* window =
      FiberBrowserWindow::FromWebContents(web_contents);
  tabs::TabInterface* tab =
      tabs::TabInterface::MaybeGetFromContents(web_contents);
  if (!window || !tab) {
    prompt->EndUnansweredSoon();
    return prompt;
  }
  prompt->ui_ = [FiberPromptFactory
      promptWithContent:content
                  tabID:tab->GetHandle().raw_value()
                 window:window->GetNativeWindow().GetNativeNSWindow()
                actions:prompt->actions_];
  return prompt;
}

Prompt::Prompt(Callback callback)
    : callback_(std::move(callback)),
      actions_([[FiberPromptActionsBridge alloc] initWithOwner:this]) {}

Prompt::~Prompt() {
  [actions_ detachOwner];
  [ui_ close];
}

std::vector<std::u16string> Prompt::GetFieldValues() const {
  std::vector<std::u16string> values;
  for (NSString* value in ui_.fieldValues) {
    values.push_back(base::SysNSStringToUTF16(value));
  }
  return values;
}

bool Prompt::IsCheckboxChecked() const {
  return ui_.checkboxChecked;
}

void Prompt::EndUnansweredSoon() {
  base::SequencedTaskRunner::GetCurrentDefault()->PostTask(
      FROM_HERE, base::BindOnce(&Prompt::OnEnded, weak_factory_.GetWeakPtr(),
                                std::nullopt));
}

void Prompt::OnEnded(std::optional<int> button_id) {
  [actions_ detachOwner];
  if (callback_) {
    // May delete this.
    std::move(callback_).Run(button_id);
  }
}

}  // namespace fiber
