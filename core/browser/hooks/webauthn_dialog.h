#ifndef FIBER_BROWSER_HOOKS_WEBAUTHN_DIALOG_H_
#define FIBER_BROWSER_HOOKS_WEBAUTHN_DIALOG_H_

#include <memory>

struct AuthenticatorRequestDialogModel;
class AuthenticatorRequestDialogViewController;

namespace fiber {

// For AuthenticatorRequestDialogViewController::Create() in a Fiber window.
// Fiber has no passkey and security key UI yet, so this cancels the request
// (the page gets NotAllowedError) rather than show Chrome's views dialog.
std::unique_ptr<AuthenticatorRequestDialogViewController>
CreateAuthenticatorRequestDialog(AuthenticatorRequestDialogModel* model);

}  // namespace fiber

#endif  // FIBER_BROWSER_HOOKS_WEBAUTHN_DIALOG_H_
