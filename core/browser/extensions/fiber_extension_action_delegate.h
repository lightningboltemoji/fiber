#ifndef FIBER_BROWSER_EXTENSIONS_FIBER_EXTENSION_ACTION_DELEGATE_H_
#define FIBER_BROWSER_EXTENSIONS_FIBER_EXTENSION_ACTION_DELEGATE_H_

#include <memory>
#include <string>

#include "base/memory/raw_ptr.h"
#include "chrome/browser/ui/extensions/extension_action_delegate.h"

namespace fiber {

class FiberExtensionsToolbar;

// Shows an extension's popup and menu for its button in a Fiber window, for
// Chrome's ExtensionActionViewModel, through the window's
// FiberExtensionsToolbar (which outlives it).
class FiberExtensionActionDelegate : public ExtensionActionDelegate {
 public:
  FiberExtensionActionDelegate(const std::string& action_id,
                               FiberExtensionsToolbar* toolbar);
  FiberExtensionActionDelegate(const FiberExtensionActionDelegate&) = delete;
  FiberExtensionActionDelegate& operator=(const FiberExtensionActionDelegate&) =
      delete;
  ~FiberExtensionActionDelegate() override;

  // ExtensionActionDelegate:
  void AttachToModel(ExtensionActionViewModel* model) override;
  void DetachFromModel() override;
  void RegisterCommand() override;
  void UnregisterCommand() override;
  bool IsShowingPopup() const override;
  void HidePopup() override;
  gfx::NativeView GetPopupNativeView() override;
  void TriggerPopup(std::unique_ptr<extensions::ExtensionViewHost> host,
                    PopupShowAction show_action,
                    bool by_user,
                    ShowPopupCallback callback) override;
  void ShowContextMenuAsFallback() override;
  void CloseExtensionsMenuIfOpen() override;

 private:
  const std::string action_id_;
  const raw_ptr<FiberExtensionsToolbar> toolbar_;
  raw_ptr<ExtensionActionViewModel> model_ = nullptr;
};

}  // namespace fiber

#endif  // FIBER_BROWSER_EXTENSIONS_FIBER_EXTENSION_ACTION_DELEGATE_H_
