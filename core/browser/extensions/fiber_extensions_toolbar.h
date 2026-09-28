#ifndef FIBER_BROWSER_EXTENSIONS_FIBER_EXTENSIONS_TOOLBAR_H_
#define FIBER_BROWSER_EXTENSIONS_FIBER_EXTENSIONS_TOOLBAR_H_

#include <map>
#include <memory>
#include <string>

#include "base/memory/raw_ptr.h"
#include "base/memory/weak_ptr.h"
#include "base/scoped_observation.h"
#include "chrome/browser/ui/extensions/extension_popup_types.h"
#include "chrome/browser/ui/extensions/extensions_toolbar_view_model.h"
#include "extensions/browser/extension_action_icon_factory.h"
#include "ui/base/unowned_user_data/scoped_unowned_user_data.h"

@class FiberExtensionsActionsBridge;
@class NSEvent;
@class NSView;
@protocol FiberExtensions;

class BrowserWindowInterface;

namespace extensions {
class ExtensionViewHost;
}  // namespace extensions

namespace fiber {

class FiberExtensionPopup;

// A Fiber window's extensions, in its toolbar and extensions menu
// (FiberExtensions). Chrome's toolbar view model decides what's there, runs
// what the user clicks, and is the window's ExtensionsContainer, which
// chrome.action.openPopup() and the like find; each extension's button is
// Chrome's ExtensionActionViewModel, with a FiberExtensionActionDelegate
// showing its popup here. As Android's ExtensionsToolbarAndroid does.
class FiberExtensionsToolbar
    : public ExtensionsToolbarViewModel::Delegate,
      public ExtensionsToolbarViewModel::Observer,
      public extensions::ExtensionActionIconFactory::Observer {
 public:
  FiberExtensionsToolbar(BrowserWindowInterface* browser,
                         id<FiberExtensions> ui);
  FiberExtensionsToolbar(const FiberExtensionsToolbar&) = delete;
  FiberExtensionsToolbar& operator=(const FiberExtensionsToolbar&) = delete;
  ~FiberExtensionsToolbar() override;

  // Called by the UI's actions.
  void RunAction(const std::string& action_id, bool from_menu);
  void SetActionPinned(const std::string& action_id, bool pinned);
  void ShowActionMenu(const std::string& action_id,
                      NSEvent* event,
                      NSView* view);
  void ManageExtensions();

  // Called by each action's FiberExtensionActionDelegate.
  bool IsShowingPopup(const std::string& action_id) const;
  void HidePopup();
  NSView* GetPopupNativeView() const;
  void TriggerPopup(const std::string& action_id,
                    std::unique_ptr<extensions::ExtensionViewHost> host,
                    PopupShowAction show_action,
                    ShowPopupCallback callback);
  void ShowActionMenuAsFallback(const std::string& action_id);

  // ExtensionsToolbarViewModel::Delegate:
  std::unique_ptr<ExtensionActionViewModel> CreateActionViewModel(
      const ToolbarActionsModel::ActionId& action_id,
      ExtensionsContainer* extensions_container) override;
  void HideActivePopup() override;
  void CloseExtensionsMenuIfOpen() override;
  bool CanShowToolbarActionPopupForAPICall(
      const ToolbarActionsModel::ActionId& action_id) override;
  void ToggleExtensionsMenu() override;

  // ExtensionsToolbarViewModel::Observer:
  void OnActionsInitialized() override;
  void OnActionAdded(const ToolbarActionsModel::ActionId& action_id) override;
  void OnActionRemoved(const ToolbarActionsModel::ActionId& action_id) override;
  void OnActionUpdated(const ToolbarActionsModel::ActionId& action_id) override;
  void OnPinnedActionsChanged() override;
  void OnActiveWebContentsChanged(bool is_same_document,
                                  content::WebContents* web_contents) override;

  // extensions::ExtensionActionIconFactory::Observer:
  void OnIconUpdated() override;

 private:
  // Loads the icon of the extension with `action_id`, which the UI shows
  // without Chrome's badge.
  void AddIconFactory(const ToolbarActionsModel::ActionId& action_id);

  // Deletes the popup, if it's still the one numbered `generation`.
  void OnPopupClosed(int generation);

  // Sends the UI the extensions soon, coalescing a burst of updates (a
  // content blocker's count, say, as a page loads).
  void ScheduleUpdate();
  void Update();

  const raw_ptr<BrowserWindowInterface> browser_;
  id<FiberExtensions> __strong ui_;
  FiberExtensionsActionsBridge* __strong actions_;
  std::unique_ptr<ExtensionsToolbarViewModel> view_model_;
  // Makes the view model the window's ExtensionsContainer.
  ui::ScopedUnownedUserData<ExtensionsContainer> container_user_data_;
  base::ScopedObservation<ExtensionsToolbarViewModel,
                          ExtensionsToolbarViewModel::Observer>
      view_model_observation_{this};
  std::map<ToolbarActionsModel::ActionId,
           std::unique_ptr<extensions::ExtensionActionIconFactory>>
      icon_factories_;
  // The popup that's open, if any, whose it is, and how many there have been.
  std::unique_ptr<FiberExtensionPopup> popup_;
  std::string popup_action_id_;
  int popup_generation_ = 0;
  // The active tab, whose switching away closes the popup.
  base::WeakPtr<content::WebContents> active_contents_;
  bool update_scheduled_ = false;
  base::WeakPtrFactory<FiberExtensionsToolbar> weak_factory_{this};
};

}  // namespace fiber

#endif  // FIBER_BROWSER_EXTENSIONS_FIBER_EXTENSIONS_TOOLBAR_H_
