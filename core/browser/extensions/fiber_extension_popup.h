#ifndef FIBER_BROWSER_EXTENSIONS_FIBER_EXTENSION_POPUP_H_
#define FIBER_BROWSER_EXTENSIONS_FIBER_EXTENSION_POPUP_H_

#include <memory>

#include "base/functional/callback.h"
#include "chrome/browser/extensions/extension_view.h"
#include "chrome/browser/ui/extensions/extension_popup_types.h"
#include "content/public/browser/web_contents_observer.h"

@class FiberExtensionPopupActionsBridge;
@class NSView;
@protocol FiberExtensionPopup;
@protocol FiberExtensions;

namespace extensions {
class ExtensionHost;
class ExtensionViewHost;
}  // namespace extensions

namespace fiber {

// An extension's popup page (`host`), shown from its toolbar button once
// loaded and sized as the page asks. When it closes, it runs `closed` soon
// after, for its owner to delete it; deleting it closes it.
class FiberExtensionPopup : public extensions::ExtensionView,
                            public content::WebContentsObserver {
 public:
  FiberExtensionPopup(std::unique_ptr<extensions::ExtensionViewHost> host,
                      id<FiberExtensions> ui,
                      const std::string& action_id,
                      PopupShowAction show_action,
                      ShowPopupCallback shown_callback,
                      base::OnceClosure closed);
  FiberExtensionPopup(const FiberExtensionPopup&) = delete;
  FiberExtensionPopup& operator=(const FiberExtensionPopup&) = delete;
  ~FiberExtensionPopup() override;

  // The page's view.
  NSView* GetContentsView() const;

  // Called by the popup's actions.
  void OnClosedByUser();

  // extensions::ExtensionView:
  gfx::NativeView GetNativeView() override;
  void ResizeDueToAutoResize(content::WebContents* web_contents,
                             const gfx::Size& new_size) override;
  void RenderFrameCreated(content::RenderFrameHost* render_frame_host) override;
  bool HandleKeyboardEvent(content::WebContents* source,
                           const input::NativeWebKeyboardEvent& event) override;
  void OnLoaded() override;

  // content::WebContentsObserver:
  void RenderFrameHostChanged(content::RenderFrameHost* old_host,
                              content::RenderFrameHost* new_host) override;

 private:
  // Sizes the page to its content, within a popup's limits.
  void SetUpMainFrame(content::RenderFrameHost* render_frame_host);
  // The page called window.close(), or the user pressed Escape.
  void OnHostClosed(extensions::ExtensionHost* host);

  std::unique_ptr<extensions::ExtensionViewHost> host_;
  const bool inspect_;
  ShowPopupCallback shown_callback_;
  base::OnceClosure closed_;
  FiberExtensionPopupActionsBridge* __strong actions_;
  id<FiberExtensionPopup> __strong ui_;
};

}  // namespace fiber

#endif  // FIBER_BROWSER_EXTENSIONS_FIBER_EXTENSION_POPUP_H_
