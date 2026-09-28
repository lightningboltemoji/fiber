#include "fiber/browser/context_menu/menu_model_menu.h"

#import <AppKit/AppKit.h>

#include <optional>
#include <vector>

#import "FiberBridge/FiberContextMenu.h"
#import "base/mac/scoped_sending_event.h"
#include "base/memory/weak_ptr.h"
#include "base/strings/sys_string_conversions.h"
#include "base/task/current_thread.h"
#include "ui/base/l10n/l10n_util_mac.h"
#include "ui/base/models/menu_model.h"
#include "ui/events/event_constants.h"

// Records which item the user chose.
@interface FiberMenuModelMenuActions : NSObject <FiberContextMenuActions>
@property(readonly) NSInteger chosenItemID;
@end

@implementation FiberMenuModelMenuActions

@synthesize chosenItemID = _chosenItemID;

- (instancetype)init {
  if ((self = [super init])) {
    _chosenItemID = -1;
  }
  return self;
}

- (void)contextMenuWillOpen {
}

- (void)contextMenuDidClose {
}

- (void)contextMenuDidSelectItemWithID:(NSInteger)itemID {
  _chosenItemID = itemID;
}

@end

namespace fiber {

namespace {

// An item in the UI's menu: the item at `index` in `model`, the menu's model
// or one of its submenus'.
struct Item {
  base::WeakPtr<ui::MenuModel> model;
  size_t index;
};

FiberContextMenuItem* Separator() {
  return [[FiberContextMenuItem alloc]
      initWithKind:FiberContextMenuItemKindSeparator
            itemID:-1
             title:@""
        symbolName:nil
           enabled:NO
           checked:NO
           submenu:@[]];
}

// The UI's items for `model`'s visible ones, recorded in `items`, which their
// IDs index.
NSArray<FiberContextMenuItem*>* ItemsFromModel(ui::MenuModel* model,
                                               std::vector<Item>& items) {
  NSMutableArray<FiberContextMenuItem*>* result = [NSMutableArray array];
  // Separators only go between items that are shown, one at a time.
  bool separate = false;
  for (size_t index = 0; index < model->GetItemCount(); ++index) {
    if (!model->IsVisibleAt(index)) {
      continue;
    }
    const ui::MenuModel::ItemType type = model->GetTypeAt(index);
    if (type == ui::MenuModel::TYPE_SEPARATOR) {
      separate = result.count > 0;
      continue;
    }
    FiberContextMenuItemKind kind = FiberContextMenuItemKindCommand;
    NSArray<FiberContextMenuItem*>* submenu = @[];
    if (type == ui::MenuModel::TYPE_SUBMENU) {
      kind = FiberContextMenuItemKindSubmenu;
      submenu = ItemsFromModel(model->GetSubmenuModelAt(index), items);
      if (submenu.count == 0) {
        continue;
      }
    }
    if (separate) {
      [result addObject:Separator()];
      separate = false;
    }
    const std::u16string label = model->GetLabelAt(index);
    const NSInteger item_id = items.size();
    items.push_back({model->AsWeakPtr(), index});
    [result addObject:[[FiberContextMenuItem alloc]
                          initWithKind:kind
                                itemID:item_id
                                 title:model->MayHaveMnemonicsAt(index)
                                           ? l10n_util::FixUpWindowsStyleLabel(
                                                 label)
                                           : base::SysUTF16ToNSString(label)
                            symbolName:nil
                               enabled:model->IsEnabledAt(index)
                               checked:model->IsItemCheckedAt(index)
                               submenu:submenu]];
  }
  return result;
}

}  // namespace

void RunMenuModel(ui::MenuModel* model, NSEvent* event, NSView* view) {
  base::WeakPtr<ui::MenuModel> root = model->AsWeakPtr();
  std::vector<Item> items;
  NSArray<FiberContextMenuItem*>* menu_items = ItemsFromModel(model, items);
  if (menu_items.count == 0) {
    return;
  }
  FiberMenuModelMenuActions* actions = [[FiberMenuModelMenuActions alloc] init];
  id<FiberContextMenu> menu = [FiberContextMenuFactory menuWithItems:menu_items
                                                             actions:actions];
  model->MenuWillShow();
  {
    // Chrome's tasks keep running while the menu is open, and a window closing
    // meanwhile waits until the event is done.
    base::CurrentThread::ScopedAllowApplicationTasksInNativeNestedLoop allow;
    base::mac::ScopedSendingEvent sending_event;
    [menu popUpWithEvent:event inView:view];
  }
  // Runs the chosen item after the menu's gone, as the item may put up
  // something of its own (a prompt to remove the extension, say).
  const NSInteger chosen = actions.chosenItemID;
  if (chosen >= 0 && static_cast<size_t>(chosen) < items.size()) {
    const Item& item = items[chosen];
    if (item.model) {
      item.model->ActivatedAt(item.index, ui::EF_NONE);
    }
  }
  if (root) {
    root->MenuWillClose();
  }
}

}  // namespace fiber
