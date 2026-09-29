#include "fiber/browser/hooks/autofill_prompts.h"

#include <optional>
#include <utility>

#include "base/functional/bind.h"
#include "base/location.h"
#include "base/task/sequenced_task_runner.h"

namespace fiber {

namespace {

using autofill::AutofillClient;
using autofill::payments::PaymentsAutofillClient;

// Soon, as Chrome's bubbles answer: the caller isn't expecting it within.
void PostAnswer(base::OnceClosure answer) {
  base::SequencedTaskRunner::GetCurrentDefault()->PostTask(FROM_HERE,
                                                           std::move(answer));
}

}  // namespace

void IgnoreSaveAddressPrompt(
    AutofillClient::AddressProfileSavePromptCallback callback) {
  PostAnswer(base::BindOnce(
      [](AutofillClient::AddressProfileSavePromptCallback callback) {
        std::move(callback).Run(
            AutofillClient::AddressPromptUserDecision::kIgnored, std::nullopt);
      },
      std::move(callback)));
}

void IgnoreSaveCardPrompt(
    PaymentsAutofillClient::LocalSaveCardPromptCallback callback) {
  PostAnswer(base::BindOnce(
      std::move(callback),
      PaymentsAutofillClient::SaveCardOfferUserDecision::kIgnored));
}

void IgnoreUploadCardPrompt(
    PaymentsAutofillClient::UploadSaveCardPromptCallback callback) {
  PostAnswer(base::BindOnce(
      std::move(callback),
      PaymentsAutofillClient::SaveCardOfferUserDecision::kIgnored,
      PaymentsAutofillClient::UserProvidedCardDetails()));
}

void IgnoreSaveIbanPrompt(
    PaymentsAutofillClient::SaveIbanPromptCallback callback) {
  PostAnswer(base::BindOnce(
      [](PaymentsAutofillClient::SaveIbanPromptCallback callback) {
        std::move(callback).Run(
            PaymentsAutofillClient::SaveIbanOfferUserDecision::kIgnored, u"");
      },
      std::move(callback)));
}

}  // namespace fiber
