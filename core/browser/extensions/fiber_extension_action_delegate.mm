#include "fiber/browser/extensions/fiber_extension_action_delegate.h"

#include <utility>

#include "base/check.h"
#include "chrome/browser/extensions/extension_view_host.h"
#include "fiber/browser/extensions/fiber_extensions_toolbar.h"

namespace fiber {

FiberExtensionActionDelegate::FiberExtensionActionDelegate(
    const std::string& action_id,
    FiberExtensionsToolbar* toolbar)
    : action_id_(action_id), toolbar_(toolbar) {}

FiberExtensionActionDelegate::~FiberExtensionActionDelegate() = default;

void FiberExtensionActionDelegate::AttachToModel(
    ExtensionActionViewModel* model) {
  CHECK(model);
  CHECK(!model_);
  model_ = model;
}

void FiberExtensionActionDelegate::DetachFromModel() {
  CHECK(model_);
  model_ = nullptr;
}

void FiberExtensionActionDelegate::RegisterCommand() {
  // Fiber has no registry for extensions' keyboard shortcuts.
}

void FiberExtensionActionDelegate::UnregisterCommand() {}

bool FiberExtensionActionDelegate::IsShowingPopup() const {
  return toolbar_->IsShowingPopup(action_id_);
}

void FiberExtensionActionDelegate::HidePopup() {
  if (IsShowingPopup()) {
    toolbar_->HidePopup();
  }
}

gfx::NativeView FiberExtensionActionDelegate::GetPopupNativeView() {
  return IsShowingPopup() ? gfx::NativeView(toolbar_->GetPopupNativeView())
                          : gfx::NativeView();
}

void FiberExtensionActionDelegate::TriggerPopup(
    std::unique_ptr<extensions::ExtensionViewHost> host,
    PopupShowAction show_action,
    bool by_user,
    ShowPopupCallback callback) {
  toolbar_->TriggerPopup(action_id_, std::move(host), show_action,
                         std::move(callback));
}

void FiberExtensionActionDelegate::ShowContextMenuAsFallback() {
  toolbar_->ShowActionMenuAsFallback(action_id_);
}

void FiberExtensionActionDelegate::CloseExtensionsMenuIfOpen() {
  toolbar_->CloseExtensionsMenuIfOpen();
}

}  // namespace fiber
