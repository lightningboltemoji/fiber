#ifndef FIBER_BROWSER_HOOKS_AUTOFILL_PROMPTS_H_
#define FIBER_BROWSER_HOOKS_AUTOFILL_PROMPTS_H_

#include "components/autofill/core/browser/foundations/autofill_client.h"
#include "components/autofill/core/browser/payments/payments_autofill_client.h"

// Chrome's offers about what was typed into a form (to save an address, a
// card, an IBAN) are views bubbles. Until Fiber has its own, each offer in a
// Fiber window is answered soon, as ignored: nothing changes. Called from
// ChromeAutofillClient and ChromePaymentsAutofillClient.
namespace fiber {

void IgnoreSaveAddressPrompt(
    autofill::AutofillClient::AddressProfileSavePromptCallback callback);

void IgnoreSaveCardPrompt(
    autofill::payments::PaymentsAutofillClient::LocalSaveCardPromptCallback
        callback);

void IgnoreUploadCardPrompt(
    autofill::payments::PaymentsAutofillClient::UploadSaveCardPromptCallback
        callback);

void IgnoreSaveIbanPrompt(
    autofill::payments::PaymentsAutofillClient::SaveIbanPromptCallback
        callback);

// The offer to ask for Touch ID or the Mac's password before filling a card.
void IgnoreMandatoryReauthPrompt(base::RepeatingClosure close_callback);

}  // namespace fiber

#endif  // FIBER_BROWSER_HOOKS_AUTOFILL_PROMPTS_H_
