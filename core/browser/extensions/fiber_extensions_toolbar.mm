#include "fiber/browser/extensions/fiber_extensions_toolbar.h"

#import <AppKit/AppKit.h>

#include <algorithm>
#include <utility>
#include <vector>

#import "FiberBridge/FiberExtensions.h"
#include "base/functional/bind.h"
#include "base/i18n/string_compare.h"
#include "base/memory/raw_ptr.h"
#include "base/strings/sys_string_conversions.h"
#include "base/task/sequenced_task_runner.h"
#include "chrome/app/chrome_command_ids.h"
#include "chrome/browser/extensions/extension_context_menu_model.h"
#include "chrome/browser/extensions/extension_view_host.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/ui/browser_commands.h"
#include "chrome/browser/ui/browser_window.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#include "chrome/browser/ui/extensions/extension_action_view_model.h"
#include "chrome/browser/ui/tabs/tab_strip_model.h"
#include "chrome/browser/ui/toolbar/toolbar_action_view_model.h"
#include "chrome/browser/ui/toolbar/toolbar_actions_model.h"
#include "components/sessions/content/session_tab_helper.h"
#include "content/public/browser/web_contents.h"
#include "extensions/browser/extension_action.h"
#include "extensions/browser/extension_action_manager.h"
#include "extensions/browser/extension_registry.h"
#include "fiber/browser/context_menu/menu_model_menu.h"
#include "fiber/browser/extensions/fiber_extension_action_delegate.h"
#include "fiber/browser/extensions/fiber_extension_popup.h"
#include "skia/ext/skia_utils_mac.h"
#include "third_party/icu/source/i18n/unicode/coll.h"
#include "ui/gfx/image/image.h"
#include "ui/gfx/image/image_skia.h"
#include "ui/gfx/image/image_skia_util_mac.h"

// Forwards what the user does with the window's extensions to its
// FiberExtensionsToolbar.
@interface FiberExtensionsActionsBridge : NSObject <FiberExtensionsActions>
- (instancetype)initWithOwner:(fiber::FiberExtensionsToolbar*)owner;
- (void)detachOwner;
@end

@implementation FiberExtensionsActionsBridge {
  raw_ptr<fiber::FiberExtensionsToolbar> _owner;
}

- (instancetype)initWithOwner:(fiber::FiberExtensionsToolbar*)owner {
  if ((self = [super init])) {
    _owner = owner;
  }
  return self;
}

- (void)detachOwner {
  _owner = nullptr;
}

- (void)runExtensionWithID:(NSString*)extensionID fromMenu:(BOOL)fromMenu {
  if (_owner) {
    _owner->RunAction(base::SysNSStringToUTF8(extensionID), fromMenu);
  }
}

- (void)setPinned:(BOOL)pinned forExtensionWithID:(NSString*)extensionID {
  if (_owner) {
    _owner->SetActionPinned(base::SysNSStringToUTF8(extensionID), pinned);
  }
}

- (void)showMenuForExtensionWithID:(NSString*)extensionID
                             event:(NSEvent*)event
                              view:(NSView*)view {
  if (_owner) {
    _owner->ShowActionMenu(base::SysNSStringToUTF8(extensionID), event, view);
  }
}

- (void)manageExtensions {
  if (_owner) {
    _owner->ManageExtensions();
  }
}

@end

namespace fiber {

namespace {

// An extension's icon loads after it's first asked for, into the same image,
// so it's converted afresh each time: gfx::Image keeps the NSImage it first
// made, which would be the blank one.
NSImage* IconImage(const gfx::Image& icon) {
  return icon.IsEmpty() ? nil : gfx::NSImageFromImageSkia(icon.AsImageSkia());
}

// Nil for a transparent color, which means the default.
NSColor* BadgeColor(SkColor color) {
  return SkColorGetA(color) == SK_AlphaTRANSPARENT
             ? nil
             : skia::SkColorToSRGBNSColor(color);
}

}  // namespace

FiberExtensionsToolbar::FiberExtensionsToolbar(BrowserWindowInterface* browser,
                                               id<FiberExtensions> ui)
    : browser_(browser),
      ui_(ui),
      actions_([[FiberExtensionsActionsBridge alloc] initWithOwner:this]),
      view_model_(std::make_unique<ExtensionsToolbarViewModel>(
          this,
          browser,
          ToolbarActionsModel::Get(browser->GetProfile()))),
      container_user_data_(browser->GetUnownedUserDataHost(), *view_model_) {
  ui_.actions = actions_;
  view_model_observation_.Observe(view_model_.get());
  if (view_model_->AreActionsInitialized()) {
    // The view model created the actions before it was observed.
    OnActionsInitialized();
  }
  if (content::WebContents* contents =
          browser_->GetTabStripModel()->GetActiveWebContents()) {
    active_contents_ = contents->GetWeakPtr();
  }
}

FiberExtensionsToolbar::~FiberExtensionsToolbar() {
  [actions_ detachOwner];
  // Before the actions go, which expect their popups gone.
  popup_.reset();
}

void FiberExtensionsToolbar::RunAction(const std::string& action_id,
                                       bool from_menu) {
  if (!view_model_->GetActionModelForId(action_id)) {
    return;
  }
  // Clicking an extension whose popup is open closes it.
  if (IsShowingPopup(action_id)) {
    HidePopup();
    return;
  }
  view_model_->ExecuteUserAction(
      action_id, from_menu
                     ? ToolbarActionViewModel::InvocationSource::kMenuEntry
                     : ToolbarActionViewModel::InvocationSource::kToolbarButton);
}

void FiberExtensionsToolbar::SetActionPinned(const std::string& action_id,
                                             bool pinned) {
  ToolbarActionsModel* model =
      ToolbarActionsModel::Get(browser_->GetProfile());
  if (browser_->GetProfile()->IsOffTheRecord() || !model->HasAction(action_id) ||
      model->IsActionForcePinned(action_id) ||
      model->IsActionPinned(action_id) == pinned) {
    return;
  }
  model->SetActionVisibility(action_id, pinned);
}

void FiberExtensionsToolbar::ShowActionMenu(const std::string& action_id,
                                            NSEvent* event,
                                            NSView* view) {
  ToolbarActionViewModel* action = view_model_->GetActionModelForId(action_id);
  if (!action) {
    return;
  }
  ui::MenuModel* menu = action->GetContextMenu(
      extensions::ExtensionContextMenuModel::ContextMenuSource::kToolbarAction);
  if (menu) {
    RunMenuModel(menu, event, view);
  }
}

void FiberExtensionsToolbar::ManageExtensions() {
  chrome::ExecuteCommand(browser_, IDC_MANAGE_EXTENSIONS);
}

bool FiberExtensionsToolbar::IsShowingPopup(
    const std::string& action_id) const {
  return popup_ && popup_action_id_ == action_id;
}

void FiberExtensionsToolbar::HidePopup() {
  popup_.reset();
  popup_action_id_.clear();
}

NSView* FiberExtensionsToolbar::GetPopupNativeView() const {
  return popup_ ? popup_->GetContentsView() : nil;
}

void FiberExtensionsToolbar::TriggerPopup(
    const std::string& action_id,
    std::unique_ptr<extensions::ExtensionViewHost> host,
    PopupShowAction show_action,
    ShowPopupCallback callback) {
  // One popup at a time.
  HidePopup();
  popup_action_id_ = action_id;
  popup_ = std::make_unique<FiberExtensionPopup>(
      std::move(host), ui_, action_id, show_action, std::move(callback),
      base::BindOnce(&FiberExtensionsToolbar::OnPopupClosed,
                     weak_factory_.GetWeakPtr(), ++popup_generation_));
}

void FiberExtensionsToolbar::ShowActionMenuAsFallback(
    const std::string& action_id) {
  [ui_ showMenuForExtensionWithID:base::SysUTF8ToNSString(action_id)];
}

void FiberExtensionsToolbar::OnPopupClosed(int generation) {
  if (generation == popup_generation_) {
    HidePopup();
  }
}

// ExtensionsToolbarViewModel::Delegate:

std::unique_ptr<ExtensionActionViewModel>
FiberExtensionsToolbar::CreateActionViewModel(
    const ToolbarActionsModel::ActionId& action_id,
    ExtensionsContainer* extensions_container) {
  return ExtensionActionViewModel::Create(
      action_id, browser_,
      std::make_unique<FiberExtensionActionDelegate>(action_id, this));
}

void FiberExtensionsToolbar::HideActivePopup() {
  HidePopup();
}

void FiberExtensionsToolbar::CloseExtensionsMenuIfOpen() {
  [ui_ closeMenu];
}

bool FiberExtensionsToolbar::CanShowToolbarActionPopupForAPICall(
    const ToolbarActionsModel::ActionId& action_id) {
  // As in Chrome: not over another popup, nor in a window in the background.
  BrowserWindow* window = BrowserWindow::FromBrowser(browser_);
  return !popup_ && window && window->IsActive();
}

void FiberExtensionsToolbar::ToggleExtensionsMenu() {
  [ui_ toggleMenu];
}

// ExtensionsToolbarViewModel::Observer:

void FiberExtensionsToolbar::OnActionsInitialized() {
  for (const ToolbarActionsModel::ActionId& action_id :
       view_model_->GetAllActionIds()) {
    AddIconFactory(action_id);
  }
  Update();
}

void FiberExtensionsToolbar::OnActionAdded(
    const ToolbarActionsModel::ActionId& action_id) {
  AddIconFactory(action_id);
  ScheduleUpdate();
}

void FiberExtensionsToolbar::OnActionRemoved(
    const ToolbarActionsModel::ActionId& action_id) {
  // While its view model is still alive, which expects it gone.
  if (IsShowingPopup(action_id)) {
    HidePopup();
  }
  icon_factories_.erase(action_id);
  ScheduleUpdate();
}

void FiberExtensionsToolbar::OnActionUpdated(
    const ToolbarActionsModel::ActionId& action_id) {
  ScheduleUpdate();
}

void FiberExtensionsToolbar::OnPinnedActionsChanged() {
  ScheduleUpdate();
}

void FiberExtensionsToolbar::OnActiveWebContentsChanged(
    bool is_same_document,
    content::WebContents* web_contents) {
  // A popup is for the tab it opened on, as in Chrome.
  if (web_contents != active_contents_.get()) {
    HidePopup();
    active_contents_ =
        web_contents ? web_contents->GetWeakPtr() : nullptr;
  }
  ScheduleUpdate();
}

// extensions::ExtensionActionIconFactory::Observer:

void FiberExtensionsToolbar::OnIconUpdated() {
  ScheduleUpdate();
}

void FiberExtensionsToolbar::AddIconFactory(
    const ToolbarActionsModel::ActionId& action_id) {
  Profile* profile = browser_->GetProfile();
  const extensions::Extension* extension =
      extensions::ExtensionRegistry::Get(profile)
          ->enabled_extensions()
          .GetByID(action_id);
  extensions::ExtensionAction* action =
      extension ? extensions::ExtensionActionManager::Get(profile)
                      ->GetExtensionAction(*extension)
                : nullptr;
  if (action) {
    icon_factories_[action_id] =
        std::make_unique<extensions::ExtensionActionIconFactory>(extension,
                                                                 action, this);
  }
}

void FiberExtensionsToolbar::ScheduleUpdate() {
  if (update_scheduled_) {
    return;
  }
  update_scheduled_ = true;
  base::SequencedTaskRunner::GetCurrentDefault()->PostTask(
      FROM_HERE, base::BindOnce(&FiberExtensionsToolbar::Update,
                                weak_factory_.GetWeakPtr()));
}

void FiberExtensionsToolbar::Update() {
  update_scheduled_ = false;
  Profile* profile = browser_->GetProfile();
  ToolbarActionsModel* actions_model = ToolbarActionsModel::Get(profile);
  extensions::ExtensionRegistry* registry =
      extensions::ExtensionRegistry::Get(profile);
  extensions::ExtensionActionManager* action_manager =
      extensions::ExtensionActionManager::Get(profile);
  content::WebContents* contents =
      browser_->GetTabStripModel()->GetActiveWebContents();
  const int tab_id = sessions::SessionTabHelper::IdForTab(contents).id();

  // By name, as Chrome's extensions menu lists them.
  struct Entry {
    ToolbarActionsModel::ActionId id;
    raw_ptr<ToolbarActionViewModel> action;
    std::u16string name;
  };
  std::vector<Entry> entries;
  for (const ToolbarActionsModel::ActionId& id :
       view_model_->GetAllActionIds()) {
    if (ToolbarActionViewModel* action = view_model_->GetActionModelForId(id)) {
      entries.push_back({id, action, action->GetActionName()});
    }
  }
  UErrorCode error = U_ZERO_ERROR;
  std::unique_ptr<icu::Collator> collator(icu::Collator::createInstance(error));
  if (U_FAILURE(error)) {
    collator.reset();
  }
  std::ranges::stable_sort(entries, [&](const Entry& a, const Entry& b) {
    return collator ? base::i18n::CompareString16WithCollator(
                          *collator, a.name, b.name) == UCOL_LESS
                    : a.name < b.name;
  });

  NSMutableArray<FiberExtensionState*>* states = [NSMutableArray array];
  for (const Entry& entry : entries) {
    const extensions::Extension* extension =
        registry->enabled_extensions().GetByID(entry.id);
    extensions::ExtensionAction* extension_action =
        extension ? action_manager->GetExtensionAction(*extension) : nullptr;
    if (!extension_action) {
      continue;
    }
    auto icon_factory = icon_factories_.find(entry.id);
    gfx::Image icon = icon_factory != icon_factories_.end()
                          ? icon_factory->second->GetIcon(tab_id)
                          : gfx::Image();
    [states
        addObject:
            [[FiberExtensionState alloc]
                initWithExtensionID:base::SysUTF8ToNSString(entry.id)
                               name:base::SysUTF16ToNSString(entry.name)
                            tooltip:base::SysUTF16ToNSString(
                                        entry.action->GetTooltip(contents))
                               icon:IconImage(icon)
                          badgeText:base::SysUTF8ToNSString(
                                        extension_action->GetDisplayBadgeText(
                                            tab_id))
                     badgeTextColor:BadgeColor(
                                        extension_action->GetBadgeTextColor(
                                            tab_id))
               badgeBackgroundColor:BadgeColor(
                                        extension_action
                                            ->GetBadgeBackgroundColor(tab_id))
                            enabled:contents &&
                                    entry.action->IsEnabled(contents)
                             pinned:actions_model->IsActionPinned(entry.id)
                       canTogglePin:!profile->IsOffTheRecord() &&
                                    !actions_model->IsActionForcePinned(
                                        entry.id)]];
  }

  NSMutableArray<NSString*>* pinned_ids = [NSMutableArray array];
  if (ToolbarActionsModel::CanShowActionsInToolbar(*browser_)) {
    for (const ToolbarActionsModel::ActionId& id :
         view_model_->GetPinnedActionIds()) {
      [pinned_ids addObject:base::SysUTF8ToNSString(id)];
    }
  }
  [ui_ setExtensions:states pinnedIDs:pinned_ids];
}

}  // namespace fiber
