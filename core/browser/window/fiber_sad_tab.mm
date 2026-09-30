#include <memory>

#include "base/functional/bind.h"
#include "base/location.h"
#include "base/task/sequenced_task_runner.h"
#include "chrome/browser/ui/sad_tab.h"
#include "fiber/browser/hooks/sad_tab.h"
#include "fiber/browser/window/fiber_browser_window.h"

namespace fiber {

namespace {

// Has `web_contents`'s window show its page state again: soon, since
// SadTabHelper holds a sad tab only once SadTab::Create() returns, and lets go
// of it before deleting it.
void UpdateWindowSoon(content::WebContents* web_contents) {
  FiberBrowserWindow* window =
      FiberBrowserWindow::FromWebContents(web_contents);
  if (!window) {
    return;
  }
  base::SequencedTaskRunner::GetCurrentDefault()->PostTask(
      FROM_HERE, base::BindOnce(&FiberBrowserWindow::UpdatePageState,
                                window->GetWeakPtr()));
}

// Its window finds it through SadTabHelper, and shows it while its tab is
// active.
class FiberSadTab : public SadTab {
 public:
  FiberSadTab(content::WebContents* web_contents, SadTabKind kind)
      : SadTab(web_contents, kind) {
    // PerformAction() expects it shown, which its window does next.
    RecordFirstPaint();
    UpdateWindowSoon(web_contents);
  }

  ~FiberSadTab() override { UpdateWindowSoon(web_contents()); }
};

}  // namespace

std::unique_ptr<SadTab> CreateSadTab(content::WebContents* web_contents,
                                     SadTabKind kind) {
  return std::make_unique<FiberSadTab>(web_contents, kind);
}

}  // namespace fiber
