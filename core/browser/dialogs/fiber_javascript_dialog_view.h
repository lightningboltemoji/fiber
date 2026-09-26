#ifndef FIBER_BROWSER_DIALOGS_FIBER_JAVASCRIPT_DIALOG_VIEW_H_
#define FIBER_BROWSER_DIALOGS_FIBER_JAVASCRIPT_DIALOG_VIEW_H_

#include <string>

#include "base/functional/callback.h"
#include "base/memory/weak_ptr.h"
#include "components/javascript_dialogs/tab_modal_dialog_view.h"
#include "content/public/browser/javascript_dialog_manager.h"
#include "ui/gfx/native_ui_types.h"

@class FiberJavaScriptDialogViewActions;
@protocol FiberJavaScriptDialog;

namespace fiber {

// A JavaScript dialog for a tab in a Fiber window, shown by Fiber's UI
// (FiberJavaScriptDialogFactory) as a sheet on the window. Owns itself until
// the dialog ends.
class FiberJavaScriptDialogView
    : public javascript_dialogs::TabModalDialogView {
 public:
  FiberJavaScriptDialogView(const FiberJavaScriptDialogView&) = delete;
  FiberJavaScriptDialogView& operator=(const FiberJavaScriptDialogView&) =
      delete;

  // See javascript_dialogs::TabModalDialogManagerDelegate::CreateNewDialog().
  static base::WeakPtr<FiberJavaScriptDialogView> Show(
      gfx::NativeWindow window,
      const std::u16string& title,
      content::JavaScriptDialogType dialog_type,
      const std::u16string& message_text,
      const std::u16string& default_prompt_text,
      content::JavaScriptDialogManager::DialogClosedCallback dialog_callback,
      base::OnceClosure dialog_force_closed_callback);

  // Called by the dialog's actions when it ends. Each deletes this.
  void OnAccepted(const std::u16string& input);
  void OnCancelled();
  void OnDismissed();

  // javascript_dialogs::TabModalDialogView:
  void CloseDialogWithoutCallback() override;
  std::u16string GetUserInput() override;

 private:
  FiberJavaScriptDialogView(
      content::JavaScriptDialogManager::DialogClosedCallback dialog_callback,
      base::OnceClosure dialog_force_closed_callback);
  ~FiberJavaScriptDialogView() override;

  content::JavaScriptDialogManager::DialogClosedCallback dialog_callback_;
  base::OnceClosure dialog_force_closed_callback_;
  FiberJavaScriptDialogViewActions* __strong actions_;
  id<FiberJavaScriptDialog> __strong dialog_;
  base::WeakPtrFactory<FiberJavaScriptDialogView> weak_factory_{this};
};

}  // namespace fiber

#endif  // FIBER_BROWSER_DIALOGS_FIBER_JAVASCRIPT_DIALOG_VIEW_H_
