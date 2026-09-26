#ifndef FIBER_BROWSER_FIBER_WINDOW_H_
#define FIBER_BROWSER_FIBER_WINDOW_H_

#include <memory>
#include <string>

#include "base/memory/raw_ptr.h"
#include "base/memory/weak_ptr.h"
#include "chrome/browser/profiles/keep_alive/scoped_profile_keep_alive.h"
#include "content/public/browser/web_contents_delegate.h"
#include "content/public/browser/web_contents_observer.h"

@class FiberWindowController;
class GURL;
class Profile;

namespace fiber {

// A top-level Fiber browser window: native AppKit chrome around a single
// WebContents. Owns itself and is deleted after its NSWindow closes. The
// WebContents is available through WebContentsObserver::web_contents().
class FiberWindow : public content::WebContentsDelegate,
                    public content::WebContentsObserver {
 public:
  // Opens a window with a new WebContents, navigated to `url` if valid.
  static FiberWindow* Create(Profile* profile, const GURL& url);
  // Opens a window around an existing WebContents, e.g. a page-opened popup.
  static FiberWindow* CreateWithContents(
      Profile* profile,
      std::unique_ptr<content::WebContents> web_contents);
  // Synchronously destroys every window. Used at shutdown, before profiles are
  // destroyed and when posted tasks would no longer run.
  static void CloseAll();

  FiberWindow(const FiberWindow&) = delete;
  FiberWindow& operator=(const FiberWindow&) = delete;

  // Toolbar and menu actions, called by FiberWindowController.
  void NavigateToInput(const std::string& input);
  void GoBack();
  void GoForward();
  void ReloadOrStop();
  void FocusWebContents();
  void NewWindow();
  void Close();

  // Called by FiberWindowController when the NSWindow is closing.
  void OnNativeWindowClosing();

  // content::WebContentsDelegate:
  content::WebContents* OpenURLFromTab(
      content::WebContents* source,
      const content::OpenURLParams& params,
      base::OnceCallback<void(content::NavigationHandle&)>
          navigation_handle_callback) override;
  content::WebContents* AddNewContents(
      content::WebContents* source,
      std::unique_ptr<content::WebContents> new_contents,
      const GURL& target_url,
      WindowOpenDisposition disposition,
      const blink::mojom::WindowFeatures& window_features,
      bool user_gesture,
      bool* was_blocked) override;
  void NavigationStateChanged(content::WebContents* source,
                              content::InvalidateTypes changed_flags) override;
  void LoadingStateChanged(content::WebContents* source,
                           bool should_show_loading_ui) override;
  void CloseContents(content::WebContents* source) override;
  bool HandleKeyboardEvent(content::WebContents* source,
                           const input::NativeWebKeyboardEvent& event) override;
  void UpdateTargetURL(content::WebContents* source, const GURL& url) override;

  // content::WebContentsObserver:
  void LoadProgressChanged(double progress) override;

 private:
  FiberWindow(Profile* profile,
              std::unique_ptr<content::WebContents> web_contents);
  ~FiberWindow() override;

  void LoadURL(const GURL& url);
  void UpdateToolbar();
  void UpdateLoadProgress();
  void Destroy();

  raw_ptr<Profile> profile_;
  // Keeps the profile loaded while the window is open. Declared before
  // `web_contents_` so it's released after it. There's deliberately no
  // ScopedKeepAlive for the process: on macOS, AppController already keeps the
  // browser alive without windows, and quitting CHECKs that no BROWSER-origin
  // keep-alive remains and waits for all of them to go away.
  ScopedProfileKeepAlive profile_keep_alive_;
  std::unique_ptr<content::WebContents> web_contents_;
  FiberWindowController* __strong controller_;
  base::WeakPtrFactory<FiberWindow> weak_factory_{this};
};

}  // namespace fiber

#endif  // FIBER_BROWSER_FIBER_WINDOW_H_
