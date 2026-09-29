#include "fiber/browser/dialogs/prompt.h"

#import <AppKit/AppKit.h>

#include <utility>

#import "FiberBridge/FiberPrompt.h"
#include "base/memory/ptr_util.h"
#include "base/memory/raw_ptr.h"
#include "base/strings/sys_string_conversions.h"

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
  prompt->ui_ = [FiberPromptFactory promptWithContent:content
                                               window:window.GetNativeNSWindow()
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

void Prompt::OnEnded(std::optional<int> button_id) {
  [actions_ detachOwner];
  if (callback_) {
    // May delete this.
    std::move(callback_).Run(button_id);
  }
}

}  // namespace fiber
