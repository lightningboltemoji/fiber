#include "fiber/browser/palette/page_text.h"

#include <optional>
#include <utility>

#include "base/functional/bind.h"
#include "base/strings/string_util.h"
#include "components/content_extraction/content/browser/inner_text.h"
#include "components/find_in_page/find_types.h"
#include "content/public/browser/navigation_handle.h"
#include "content/public/browser/render_frame_host.h"
#include "content/public/browser/visibility.h"
#include "content/public/browser/web_contents.h"

namespace fiber {

namespace {

// After a load, for scripts to fill in the page.
constexpr base::TimeDelta kSettleDelay = base::Seconds(1);
// After the page changes its URL itself, for it to render what's new.
constexpr base::TimeDelta kSameDocumentDelay = base::Seconds(2);
// Leaving a tab reads it again only if it wasn't read this recently.
constexpr base::TimeDelta kLeaveInterval = base::Seconds(5);
// About twenty pages of prose. The rest of a longer page isn't searched.
constexpr size_t kMaxTextBytes = 64 * 1024;

}  // namespace

PageText::PageText(content::WebContents* web_contents,
                   base::RepeatingCallback<void(const std::string&)> on_text)
    : content::WebContentsObserver(web_contents), on_text_(std::move(on_text)) {
  // A tab that loaded before this was made.
  if (!web_contents->IsLoading() &&
      web_contents->GetPrimaryMainFrame()->IsRenderFrameLive()) {
    ReadSoon(kSettleDelay);
  }
}

PageText::~PageText() = default;

void PageText::Read() {
  read_timer_.Stop();
  if (!web_contents()) {
    return;
  }
  content::RenderFrameHost* frame = web_contents()->GetPrimaryMainFrame();
  if (!frame->IsRenderFrameLive()) {
    return;
  }
  last_read_ = base::TimeTicks::Now();
  content_extraction::GetInnerText(
      *frame, /*node_id=*/std::nullopt,
      base::BindOnce(&PageText::OnInnerText, weak_factory_.GetWeakPtr(),
                     page_));
}

void PageText::Reveal(const std::u16string& text) {
  if (!web_contents() || text.empty()) {
    return;
  }
  reveal_text_ = text;
  // A discarded tab reloads as it's selected.
  if (!web_contents()->IsLoading() && !web_contents()->WasDiscarded()) {
    FindRevealText();
  }
}

void PageText::ReadSoon(base::TimeDelta delay) {
  read_timer_.Start(FROM_HERE, delay,
                    base::BindOnce(&PageText::Read, base::Unretained(this)));
}

void PageText::OnInnerText(
    int page,
    std::unique_ptr<content_extraction::InnerTextResult> result) {
  if (!result || page != page_) {
    return;
  }
  // The page's text is untrusted: it's only cut to size here, and read by the
  // UI, in Swift.
  std::string text;
  base::TruncateUTF8ToByteSize(result->inner_text, kMaxTextBytes, &text);
  on_text_.Run(text);
}

void PageText::FindRevealText() {
  find_in_page::FindTabHelper* find =
      find_in_page::FindTabHelper::FromWebContents(web_contents());
  if (!find) {
    reveal_text_.clear();
    return;
  }
  if (!find_observation_.IsObserving()) {
    find_observation_.Observe(find);
  }
  find->StartFinding(std::exchange(reveal_text_, std::u16string()),
                     /*forward_direction=*/true, /*case_sensitive=*/false,
                     /*find_match=*/true);
}

void PageText::DidStopLoading() {
  if (!reveal_text_.empty()) {
    FindRevealText();
  }
  ReadSoon(kSettleDelay);
}

void PageText::PrimaryPageChanged(content::Page& page) {
  ++page_;
  read_timer_.Stop();
  on_text_.Run(std::string());
}

void PageText::DidFinishNavigation(
    content::NavigationHandle* navigation_handle) {
  if (navigation_handle->IsInPrimaryMainFrame() &&
      navigation_handle->IsSameDocument() &&
      navigation_handle->HasCommitted()) {
    ReadSoon(kSameDocumentDelay);
  }
}

void PageText::OnVisibilityChanged(content::Visibility visibility) {
  if (visibility == content::Visibility::HIDDEN &&
      !web_contents()->IsLoading() &&
      base::TimeTicks::Now() - last_read_ >= kLeaveInterval) {
    Read();
  }
}

void PageText::OnFindResultAvailable(content::WebContents* web_contents) {
  find_in_page::FindTabHelper* find =
      find_in_page::FindTabHelper::FromWebContents(web_contents);
  if (!find->find_result().final_update()) {
    return;
  }
  // The match stays selected, without find in page's highlights.
  find_observation_.Reset();
  find->StopFinding(find_in_page::SelectionAction::kKeep);
}

}  // namespace fiber
