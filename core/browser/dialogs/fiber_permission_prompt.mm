#include "fiber/browser/dialogs/fiber_permission_prompt.h"

#import <AppKit/AppKit.h>

#include <algorithm>
#include <optional>
#include <string>
#include <variant>
#include <vector>

#import "FiberBridge/FiberPrompt.h"
#include "base/check.h"
#include "base/functional/bind.h"
#include "base/location.h"
#include "base/memory/raw_ptr.h"
#include "base/memory/weak_ptr.h"
#include "base/notreached.h"
#include "base/strings/sys_string_conversions.h"
#include "base/task/sequenced_task_runner.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/ui/url_identity.h"
#include "chrome/grit/generated_resources.h"
#include "components/content_settings/core/browser/host_content_settings_map.h"
#include "components/permissions/permission_request.h"
#include "components/permissions/permission_uma_constants.h"
#include "components/permissions/permission_util.h"
#include "components/permissions/request_type.h"
#include "components/strings/grit/components_strings.h"
#include "components/url_formatter/elide_url.h"
#include "content/public/browser/web_contents.h"
#include "fiber/browser/dialogs/prompt.h"
#include "fiber/browser/window/fiber_browser_window.h"
#include "ui/base/l10n/l10n_util.h"
#include "ui/base/l10n/l10n_util_mac.h"
#include "url/gurl.h"

namespace fiber {

namespace {

using permissions::PermissionPrompt;
using permissions::PermissionRequest;
using permissions::RequestType;

enum ButtonID {
  kAllow,
  kAllowThisTime,
  kBlock,
};

// As in Chrome's prompt, a camera request goes unlisted beside one to also
// pan, tilt and zoom it.
std::vector<PermissionRequest*> VisibleRequests(
    PermissionPrompt::Delegate& delegate) {
  const bool has_camera_ptz =
      std::ranges::contains(delegate.Requests(), RequestType::kCameraPanTiltZoom,
                            &PermissionRequest::request_type);
  std::vector<PermissionRequest*> requests;
  for (const auto& request : delegate.Requests()) {
    if (!(has_camera_ptz &&
          request->request_type() == RequestType::kCameraStream)) {
      requests.push_back(request.get());
    }
  }
  return requests;
}

// Whether every request can be allowed just this once.
bool CanAllowThisTime(PermissionPrompt::Delegate& delegate) {
  for (const auto& request : delegate.Requests()) {
    std::optional<ContentSettingsType> type =
        permissions::RequestTypeToContentSettingsType(request->request_type());
    if (!type || !permissions::PermissionUtil::DoesSupportTemporaryGrants(*type)) {
      return false;
    }
  }
  return true;
}

// The asking site as Chrome's prompt names it: an extension by its name, say.
std::u16string SiteName(content::WebContents* web_contents,
                        PermissionPrompt::Delegate& delegate) {
  constexpr UrlIdentity::TypeSet kAllowedTypes = {
      UrlIdentity::Type::kDefault, UrlIdentity::Type::kChromeExtension,
      UrlIdentity::Type::kIsolatedWebApp, UrlIdentity::Type::kFile};
  constexpr UrlIdentity::FormatOptions kOptions = {
      .default_options = {
          UrlIdentity::DefaultFormatOptions::kOmitCryptographicScheme}};
  UrlIdentity identity = UrlIdentity::CreateFromUrl(
      Profile::FromBrowserContext(web_contents->GetBrowserContext()),
      delegate.GetRequestingOrigin(), kAllowedTypes, kOptions);
  if (identity.type == UrlIdentity::Type::kFile) {
    return l10n_util::GetStringUTF16(IDS_PERMISSIONS_BUBBLE_PROMPT_THIS_FILE);
  }
  return identity.name;
}

std::u16string FormatSite(const GURL& url) {
  return url_formatter::FormatUrlForSecurityDisplay(
      url, url_formatter::SchemeDisplay::OMIT_CRYPTOGRAPHIC);
}

FiberPromptContent* ContentForPrompt(content::WebContents* web_contents,
                                     PermissionPrompt::Delegate& delegate) {
  NSString* title;
  NSString* message = @"";
  NSMutableArray<FiberPromptListItem*>* items = [NSMutableArray array];
  if (delegate.Requests()[0]->ShouldUseTwoOriginPrompt()) {
    // Storage access, for a site embedded in the page: the sites it would
    // join, by the patterns the grant would cover.
    content_settings::PatternPair patterns =
        HostContentSettingsMap::GetPatternsForContentSettingsType(
            delegate.GetRequestingOrigin(), delegate.GetEmbeddingOrigin(),
            ContentSettingsType::STORAGE_ACCESS);
    const std::u16string embedded =
        FormatSite(patterns.first.ToRepresentativeUrl());
    title = l10n_util::GetNSStringF(
        IDS_STORAGE_ACCESS_PERMISSION_TWO_ORIGIN_PROMPT_TITLE, embedded);
    message = l10n_util::GetNSStringF(
        IDS_STORAGE_ACCESS_PERMISSION_TWO_ORIGIN_EXPLANATION, embedded,
        FormatSite(patterns.second.ToRepresentativeUrl()));
  } else {
    title = l10n_util::GetNSStringF(IDS_PERMISSIONS_BUBBLE_PROMPT,
                                    SiteName(web_contents, delegate));
    for (PermissionRequest* request : VisibleRequests(delegate)) {
      [items addObject:[[FiberPromptListItem alloc]
                           initWithText:base::SysUTF16ToNSString(
                                            request->GetMessageTextFragment())
                                 detail:@""]];
    }
  }

  // Granting waits on a click, and on the prompt having been up a moment, so
  // a page can't rush the user into it.
  NSMutableArray<FiberPromptButton*>* buttons = [NSMutableArray array];
  const bool can_allow_this_time = CanAllowThisTime(delegate);
  [buttons addObject:[[FiberPromptButton alloc]
                         initWithButtonID:kBlock
                                    title:l10n_util::GetNSString(
                                              can_allow_this_time
                                                  ? IDS_PERMISSION_NEVER_ALLOW
                                                  : IDS_PERMISSION_DENY)
                                     role:FiberPromptButtonRoleOther]];
  if (can_allow_this_time) {
    [buttons addObject:[[FiberPromptButton alloc]
                           initWithButtonID:kAllowThisTime
                                      title:l10n_util::GetNSString(
                                                IDS_PERMISSION_ALLOW_THIS_TIME)
                                       role:FiberPromptButtonRoleConfirm]];
  }
  [buttons addObject:[[FiberPromptButton alloc]
                         initWithButtonID:kAllow
                                    title:l10n_util::GetNSString(
                                              IDS_PERMISSION_ALLOW)
                                     role:FiberPromptButtonRoleConfirm]];

  return [[FiberPromptContent alloc] initWithIcon:nil
                                          eyebrow:@""
                                            title:title
                                          message:message
                                      listHeading:@""
                                        listItems:items
                                          buttons:buttons];
}

class FiberPermissionPrompt : public PermissionPrompt {
 public:
  FiberPermissionPrompt(gfx::NativeWindow window,
                        FiberPromptContent* content,
                        Delegate* delegate)
      : delegate_(delegate) {
    ui_ = Prompt::Show(window, content,
                       base::BindOnce(&FiberPermissionPrompt::OnEnded,
                                      base::Unretained(this)));
  }

  // PermissionPrompt:
  bool UpdateAnchor() override { return true; }
  TabSwitchingBehavior GetTabSwitchingBehavior() override {
    return kDestroyPromptButKeepRequestPending;
  }
  permissions::PermissionPromptDisposition GetPromptDisposition()
      const override {
    return permissions::PermissionPromptDisposition::CUSTOM_MODAL_DIALOG;
  }
  bool IsAskPrompt() const override { return false; }
  std::optional<gfx::Rect> GetViewBoundsInScreen() const override {
    return std::nullopt;
  }
  std::vector<permissions::ElementAnchoredBubbleVariant> GetPromptVariants()
      const override {
    return {};
  }
  std::optional<permissions::feature_params::PermissionElementPromptPosition>
  GetPromptPosition() const override {
    return std::nullopt;
  }

 private:
  void OnEnded(std::optional<int> button_id) {
    // Posted: a prompt can end as another takes its place, and answering can
    // show the next.
    base::SequencedTaskRunner::GetCurrentDefault()->PostTask(
        FROM_HERE, base::BindOnce(&FiberPermissionPrompt::Answer,
                                  weak_factory_.GetWeakPtr(), button_id));
  }

  // Destroys this. Ending without a button counts as dismissing, as closing
  // Chrome's prompt does.
  void Answer(std::optional<int> button_id) {
    if (!button_id) {
      delegate_->Dismiss(std::monostate());
      return;
    }
    switch (*button_id) {
      case kAllow:
        delegate_->Accept(std::monostate());
        return;
      case kAllowThisTime:
        delegate_->AcceptThisTime(std::monostate());
        return;
      case kBlock:
        delegate_->Deny(std::monostate());
        return;
    }
    NOTREACHED();
  }

  // Owns this.
  raw_ptr<Delegate> delegate_;
  std::unique_ptr<Prompt> ui_;
  base::WeakPtrFactory<FiberPermissionPrompt> weak_factory_{this};
};

}  // namespace

std::unique_ptr<PermissionPrompt> ShowPermissionPrompt(
    content::WebContents* web_contents,
    PermissionPrompt::Delegate* delegate) {
  FiberBrowserWindow* window = FiberBrowserWindow::FromWebContents(web_contents);
  CHECK(window);
  return std::make_unique<FiberPermissionPrompt>(
      window->GetNativeWindow(), ContentForPrompt(web_contents, *delegate),
      delegate);
}

}  // namespace fiber
