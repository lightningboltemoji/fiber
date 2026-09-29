#include "fiber/browser/hooks/webauthn_dialog.h"

#include "base/functional/bind.h"
#include "base/location.h"
#include "base/memory/raw_ptr.h"
#include "base/memory/weak_ptr.h"
#include "base/task/sequenced_task_runner.h"
#include "chrome/browser/ui/webauthn/authenticator_request_dialog_view_controller.h"
#include "chrome/browser/webauthn/authenticator_request_dialog_model.h"

namespace fiber {

namespace {

class CancelingAuthenticatorRequestDialog
    : public AuthenticatorRequestDialogViewController {
 public:
  explicit CancelingAuthenticatorRequestDialog(
      AuthenticatorRequestDialogModel* model)
      : model_(model) {
    // Posted: `model` is mid-SetStep(), and canceling can destroy the tab.
    // `model` owns this, so the weak pointer also guards `model_`.
    base::SequencedTaskRunner::GetCurrentDefault()->PostTask(
        FROM_HERE,
        base::BindOnce(&CancelingAuthenticatorRequestDialog::Cancel,
                       weak_factory_.GetWeakPtr()));
  }

 private:
  // Can destroy this.
  void Cancel() { model_->CancelAuthenticatorRequest(); }

  raw_ptr<AuthenticatorRequestDialogModel> model_;
  base::WeakPtrFactory<CancelingAuthenticatorRequestDialog> weak_factory_{
      this};
};

}  // namespace

std::unique_ptr<AuthenticatorRequestDialogViewController>
CreateAuthenticatorRequestDialog(AuthenticatorRequestDialogModel* model) {
  return std::make_unique<CancelingAuthenticatorRequestDialog>(model);
}

}  // namespace fiber
