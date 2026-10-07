#ifndef FIBER_BROWSER_DIALOGS_FIBER_APP_MODAL_DIALOG_VIEW_H_
#define FIBER_BROWSER_DIALOGS_FIBER_APP_MODAL_DIALOG_VIEW_H_

#include <memory>
#include <optional>
#include <string>

#include "components/javascript_dialogs/app_modal_dialog_view.h"

@class FiberAppModalDialogViewActions;
@protocol FiberJavaScriptDialog;
class PopunderPreventer;

namespace javascript_dialogs {
class AppModalDialogController;
}

namespace fiber {

class Prompt;

// A JavaScript dialog Chrome shows app-modally: beforeunload, in a Prompt on
// its tab, or one from a page without a tab-modal dialog manager, as a sheet.
// Cancelled outside Fiber's windows. Owns itself until it ends.
class FiberAppModalDialogView : public javascript_dialogs::AppModalDialogView {
 public:
  FiberAppModalDialogView(const FiberAppModalDialogView&) = delete;
  FiberAppModalDialogView& operator=(const FiberAppModalDialogView&) = delete;

  // javascript_dialogs::AppModalDialogManager's native dialog factory (see
  // fiber::InstallAppModalDialogFactory()).
  static javascript_dialogs::AppModalDialogView* Create(
      std::unique_ptr<javascript_dialogs::AppModalDialogController>
          controller);

  // Called by the dialog's actions when it ends. Each deletes this.
  void OnAccepted(const std::u16string& input);
  void OnCancelled();
  void OnDismissed();

  // javascript_dialogs::AppModalDialogView:
  void ShowAppModalDialog() override;
  void ActivateAppModalDialog() override;
  void CloseAppModalDialog() override;
  void AcceptAppModalDialog() override;
  void CancelAppModalDialog() override;
  bool IsShowing() const override;

 private:
  explicit FiberAppModalDialogView(
      std::unique_ptr<javascript_dialogs::AppModalDialogController>
          controller);
  ~FiberAppModalDialogView() override;

  // Deletes this.
  void OnLeavePromptEnded(std::optional<int> button_id);

  // Takes the dialog down without reporting how it ended.
  void CloseDialog();

  std::unique_ptr<javascript_dialogs::AppModalDialogController> controller_;
  std::unique_ptr<PopunderPreventer> popunder_preventer_;
  FiberAppModalDialogViewActions* __strong actions_;
  id<FiberJavaScriptDialog> __strong dialog_;
  // Instead of `dialog_`, for beforeunload.
  std::unique_ptr<Prompt> leave_prompt_;
};

}  // namespace fiber

#endif  // FIBER_BROWSER_DIALOGS_FIBER_APP_MODAL_DIALOG_VIEW_H_
