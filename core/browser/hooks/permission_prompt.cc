#include "fiber/browser/hooks/permission_prompt.h"

#include <optional>
#include <variant>
#include <vector>

#include "base/functional/bind.h"
#include "base/location.h"
#include "base/memory/raw_ptr.h"
#include "base/memory/weak_ptr.h"
#include "base/task/sequenced_task_runner.h"
#include "components/permissions/features.h"
#include "components/permissions/permission_uma_constants.h"
#include "components/permissions/permission_util.h"
#include "fiber/browser/dialogs/fiber_permission_prompt.h"

namespace fiber {

namespace {

class IgnoringPermissionPrompt : public permissions::PermissionPrompt {
 public:
  explicit IgnoringPermissionPrompt(Delegate* delegate) : delegate_(delegate) {
    // Posted: `delegate` is mid-RecreateView(), and sets this as its view
    // after. `delegate` owns this, so the weak pointer also guards `delegate_`.
    base::SequencedTaskRunner::GetCurrentDefault()->PostTask(
        FROM_HERE, base::BindOnce(&IgnoringPermissionPrompt::Ignore,
                                  weak_factory_.GetWeakPtr()));
  }

  // permissions::PermissionPrompt:
  bool UpdateAnchor() override { return true; }
  TabSwitchingBehavior GetTabSwitchingBehavior() override {
    return kDestroyPromptAndIgnoreRequest;
  }
  permissions::PermissionPromptDisposition GetPromptDisposition()
      const override {
    return permissions::PermissionPromptDisposition::NONE_VISIBLE;
  }
  bool IsAskPrompt() const override { return false; }
  std::optional<gfx::Rect> GetViewBoundsInScreen() const override {
    return std::nullopt;
  }
  std::vector<permissions::ElementAnchoredBubbleVariant> GetPromptVariants()
      const override {
    return {};
  }
  std::optional<permissions::feature_params::PermissionElementPromptPosition>
  GetPromptPosition() const override {
    return std::nullopt;
  }

 private:
  // Destroys this.
  void Ignore() { delegate_->Ignore(std::monostate()); }

  raw_ptr<Delegate> delegate_;
  base::WeakPtrFactory<IgnoringPermissionPrompt> weak_factory_{this};
};

}  // namespace

std::unique_ptr<permissions::PermissionPrompt> CreatePermissionPrompt(
    content::WebContents* web_contents,
    permissions::PermissionPrompt::Delegate* delegate) {
  if (delegate->ShouldCurrentRequestUseQuietUI() ||
      permissions::PermissionUtil::
          ShouldCurrentRequestUsePermissionElementSecondaryUI(delegate,
                                                              web_contents)) {
    return std::make_unique<IgnoringPermissionPrompt>(delegate);
  }
  return ShowPermissionPrompt(web_contents, delegate);
}

}  // namespace fiber
