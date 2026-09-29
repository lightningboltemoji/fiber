#import <AppKit/AppKit.h>

#include <memory>
#include <optional>
#include <string>
#include <utility>

#import "FiberBridge/FiberPrompt.h"
#include "base/functional/bind.h"
#include "base/memory/weak_ptr.h"
#include "base/strings/sys_string_conversions.h"
#include "base/types/optional_util.h"
#include "chrome/browser/external_protocol/external_protocol_handler.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/common/pref_names.h"
#include "chrome/grit/generated_resources.h"
#include "components/prefs/pref_service.h"
#include "components/url_formatter/elide_url.h"
#include "content/public/browser/web_contents.h"
#include "fiber/browser/dialogs/tab_prompt.h"
#include "fiber/browser/hooks/page_dialogs.h"
#include "ui/base/l10n/l10n_util.h"
#include "ui/base/l10n/l10n_util_mac.h"
#include "ui/gfx/text_elider.h"
#include "url/gurl.h"
#include "url/origin.h"

namespace fiber {

namespace {

enum ButtonID {
  kOpen,
  kCancel,
};

// Chrome's words (see ExternalProtocolDialog).
FiberPromptContent* ContentForDialog(
    content::WebContents* web_contents,
    const std::optional<url::Origin>& initiating_origin,
    const std::u16string& program_name) {
  constexpr int kMaxCommandCharsToDisplay = 32;
  std::u16string elided_program_name;
  gfx::ElideString(program_name, kMaxCommandCharsToDisplay,
                   &elided_program_name);

  NSString* message =
      !initiating_origin || initiating_origin->opaque()
          ? l10n_util::GetNSString(IDS_EXTERNAL_PROTOCOL_MESSAGE)
          : l10n_util::GetNSStringF(
                IDS_EXTERNAL_PROTOCOL_MESSAGE_WITH_INITIATING_ORIGIN,
                url_formatter::FormatOriginForSecurityDisplay(
                    *initiating_origin));

  // Offered for a trustworthy origin, unless policy says otherwise.
  NSString* checkbox_title = @"";
  if (Profile::FromBrowserContext(web_contents->GetBrowserContext())
          ->GetPrefs()
          ->GetBoolean(prefs::kExternalProtocolDialogShowAlwaysOpenCheckbox) &&
      ExternalProtocolHandler::MayRememberAllowDecisionsForThisOrigin(
          base::OptionalToPtr(initiating_origin))) {
    checkbox_title = l10n_util::GetNSStringF(
        IDS_EXTERNAL_PROTOCOL_CHECKBOX_PER_ORIGIN_TEXT,
        url_formatter::FormatOriginForSecurityDisplay(
            *initiating_origin,
            url_formatter::SchemeDisplay::OMIT_CRYPTOGRAPHIC));
  }

  // Opening waits on a click, and on the prompt having been up a moment, so
  // a page can't rush the user into it.
  return [[FiberPromptContent alloc]
       initWithIcon:nil
            eyebrow:@""
              title:l10n_util::GetNSStringF(IDS_EXTERNAL_PROTOCOL_TITLE,
                                            elided_program_name)
            message:message
        listHeading:@""
          listItems:@[]
             fields:@[]
      checkboxTitle:checkbox_title
            buttons:@[
              [[FiberPromptButton alloc]
                  initWithButtonID:kCancel
                             title:l10n_util::GetNSString(
                                       IDS_EXTERNAL_PROTOCOL_CANCEL_BUTTON_TEXT)
                              role:FiberPromptButtonRoleCancel],
              [[FiberPromptButton alloc]
                  initWithButtonID:kOpen
                             title:l10n_util::GetNSStringF(
                                       IDS_EXTERNAL_PROTOCOL_OK_BUTTON_TEXT,
                                       program_name)
                              role:FiberPromptButtonRoleConfirm],
            ]];
}

// Owns itself until the prompt ends.
class ExternalProtocolPrompt {
 public:
  ExternalProtocolPrompt(content::WebContents* web_contents,
                         const GURL& url,
                         const std::optional<url::Origin>& initiating_origin,
                         content::WeakDocumentPtr initiator_document,
                         const std::u16string& program_name)
      : web_contents_(web_contents->GetWeakPtr()),
        url_(url),
        initiating_origin_(initiating_origin),
        initiator_document_(std::move(initiator_document)) {
    ui_ = TabPrompt::Show(
        web_contents,
        ContentForDialog(web_contents, initiating_origin, program_name),
        base::BindOnce(&ExternalProtocolPrompt::OnEnded,
                       base::Unretained(this)));
  }

 private:
  // Deletes this.
  void OnEnded(std::optional<int> button_id) {
    std::unique_ptr<ExternalProtocolPrompt> self(this);
    if (button_id != kOpen) {
      ExternalProtocolHandler::RecordHandleStateMetrics(
          /*checkbox_selected=*/false, ExternalProtocolHandler::BLOCK);
      return;
    }
    const bool remember = ui_->prompt().IsCheckboxChecked();
    ExternalProtocolHandler::RecordHandleStateMetrics(
        remember, ExternalProtocolHandler::DONT_BLOCK);
    if (!web_contents_) {
      return;
    }
    if (remember) {
      ExternalProtocolHandler::SetBlockState(
          url_.GetScheme(), *initiating_origin_,
          ExternalProtocolHandler::DONT_BLOCK,
          Profile::FromBrowserContext(web_contents_->GetBrowserContext()));
    }
    ExternalProtocolHandler::LaunchUrlWithoutSecurityCheck(
        url_, web_contents_.get(), initiator_document_);
  }

  const base::WeakPtr<content::WebContents> web_contents_;
  const GURL url_;
  const std::optional<url::Origin> initiating_origin_;
  const content::WeakDocumentPtr initiator_document_;
  std::unique_ptr<TabPrompt> ui_;
};

}  // namespace

void ShowExternalProtocolDialog(
    const GURL& url,
    content::WebContents* web_contents,
    const std::optional<url::Origin>& initiating_origin,
    content::WeakDocumentPtr initiator_document,
    const std::u16string& program_name) {
  new ExternalProtocolPrompt(web_contents, url, initiating_origin,
                             std::move(initiator_document), program_name);
}

}  // namespace fiber
