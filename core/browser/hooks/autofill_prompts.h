#ifndef FIBER_BROWSER_HOOKS_AUTOFILL_PROMPTS_H_
#define FIBER_BROWSER_HOOKS_AUTOFILL_PROMPTS_H_

#include "components/autofill/core/browser/foundations/autofill_client.h"
#include "components/autofill/core/browser/payments/payments_autofill_client.h"

// Chrome's offers to save what was typed into a form (an address, a card, an
// IBAN) are views bubbles, which Fiber windows can't host. Until Fiber has its
// own, each offer in a Fiber window is answered soon, as ignored: nothing is
// saved. Called from ChromeAutofillClient and ChromePaymentsAutofillClient.
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

}  // namespace fiber

#endif  // FIBER_BROWSER_HOOKS_AUTOFILL_PROMPTS_H_
