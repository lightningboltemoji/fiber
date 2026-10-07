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
#include "fiber/browser/dialogs/prompt_site.h"
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

// The asking site, or, as Chrome's prompt has it, "This file".
std::u16string SiteName(content::WebContents* web_contents,
                        PermissionPrompt::Delegate& delegate) {
  const GURL& url = delegate.GetRequestingOrigin();
  if (url.SchemeIsFile()) {
    return l10n_util::GetStringUTF16(IDS_PERMISSIONS_BUBBLE_PROMPT_THIS_FILE);
  }
  return SiteForPrompt(
      Profile::FromBrowserContext(web_contents->GetBrowserContext()), url);
}

FiberPromptTopic TopicForRequest(RequestType type) {
  switch (type) {
    case RequestType::kGeolocation:
      return FiberPromptTopicLocation;
    case RequestType::kCameraPanTiltZoom:
    case RequestType::kCameraStream:
      return FiberPromptTopicCamera;
    case RequestType::kMicStream:
      return FiberPromptTopicMicrophone;
    case RequestType::kNotifications:
      return FiberPromptTopicNotifications;
    case RequestType::kClipboard:
      return FiberPromptTopicClipboard;
    case RequestType::kFileSystemAccess:
      return FiberPromptTopicFiles;
    case RequestType::kMultipleDownloads:
      return FiberPromptTopicDownloads;
    case RequestType::kRegisterProtocolHandler:
      return FiberPromptTopicOpenApp;
    case RequestType::kLocalNetwork:
    case RequestType::kLoopbackNetwork:
      return FiberPromptTopicLocalNetwork;
    case RequestType::kMidiSysex:
      return FiberPromptTopicMIDI;
    case RequestType::kWindowManagement:
      return FiberPromptTopicWindows;
    case RequestType::kStorageAccess:
    case RequestType::kTopLevelStorageAccess:
      return FiberPromptTopicStorageAccess;
    case RequestType::kKeyboardLock:
      return FiberPromptTopicKeyboardLock;
    case RequestType::kPointerLock:
      return FiberPromptTopicPointerLock;
    case RequestType::kArSession:
    case RequestType::kHandTracking:
    case RequestType::kVrSession:
      return FiberPromptTopicSpatial;
    default:
      return FiberPromptTopicGeneral;
  }
}

std::u16string FormatSite(const GURL& url) {
  return url_formatter::FormatUrlForSecurityDisplay(
      url, url_formatter::SchemeDisplay::OMIT_HTTP_AND_HTTPS);
}

FiberPromptContent* ContentForPrompt(content::WebContents* web_contents,
                                     PermissionPrompt::Delegate& delegate) {
  NSString* eyebrow = @"";
  NSString* title;
  NSString* message = @"";
  NSMutableArray<FiberPromptListItem*>* items = [NSMutableArray array];
  const std::vector<PermissionRequest*> requests = VisibleRequests(delegate);
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
    // The site over what it asks first, and the rest under that.
    eyebrow = l10n_util::GetNSStringF(IDS_PERMISSIONS_BUBBLE_PROMPT,
                                      SiteName(web_contents, delegate));
    title = base::SysUTF16ToNSString(requests[0]->GetMessageTextFragment());
    for (size_t i = 1; i < requests.size(); ++i) {
      [items
          addObject:[[FiberPromptListItem alloc]
                        initWithText:base::SysUTF16ToNSString(
                                         requests[i]->GetMessageTextFragment())
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

  return [[FiberPromptContent alloc]
      initWithIcon:nil
             topic:TopicForRequest(requests[0]->request_type())
           eyebrow:eyebrow
             title:title
           message:message
       listHeading:@""
         listItems:items
           buttons:buttons];
}

class FiberPermissionPrompt : public PermissionPrompt {
 public:
  FiberPermissionPrompt(content::WebContents* web_contents,
                        FiberPromptContent* content,
                        Delegate* delegate)
      : delegate_(delegate) {
    ui_ = Prompt::ShowForTab(web_contents, content,
                             base::BindOnce(&FiberPermissionPrompt::OnEnded,
                                            base::Unretained(this)));
  }

  // PermissionPrompt:
  bool UpdateAnchor() override { return true; }
  // The prompt waits, hidden, while its tab isn't active.
  TabSwitchingBehavior GetTabSwitchingBehavior() override {
    return kKeepPromptAlive;
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
  CHECK(FiberBrowserWindow::FromWebContents(web_contents));
  return std::make_unique<FiberPermissionPrompt>(
      web_contents, ContentForPrompt(web_contents, *delegate), delegate);
}

}  // namespace fiber
