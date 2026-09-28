#include "fiber/browser/context_menu/fiber_render_view_context_menu.h"

#import <AppKit/AppKit.h>

#include <string_view>

#import "FiberBridge/FiberContextMenu.h"
#include "base/apple/owned_objc.h"
#include "base/containers/fixed_flat_map.h"
#import "base/mac/scoped_sending_event.h"
#include "base/memory/raw_ptr.h"
#include "base/strings/sys_string_conversions.h"
#include "base/task/current_thread.h"
#include "chrome/app/chrome_command_ids.h"
#include "chrome/browser/extensions/context_menu_matcher.h"
#include "content/public/browser/render_widget_host_view.h"
#include "content/public/browser/web_contents.h"
#include "ui/base/cocoa/menu_utils.h"
#include "ui/base/l10n/l10n_util_mac.h"
#include "ui/base/models/menu_model.h"
#include "ui/events/event_utils.h"
#include "ui/menus/cocoa/text_services_context_menu.h"

// Forwards what the user does with the menu to its FiberRenderViewContextMenu.
@interface FiberRenderViewContextMenuActions
    : NSObject <FiberContextMenuActions>
- (instancetype)initWithOwner:(fiber::FiberRenderViewContextMenu*)owner;
- (void)detachOwner;
@end

@implementation FiberRenderViewContextMenuActions {
  raw_ptr<fiber::FiberRenderViewContextMenu> _owner;
}

- (instancetype)initWithOwner:(fiber::FiberRenderViewContextMenu*)owner {
  if ((self = [super init])) {
    _owner = owner;
  }
  return self;
}

- (void)detachOwner {
  _owner = nullptr;
}

- (void)contextMenuWillOpen {
  if (_owner) {
    _owner->OnMenuWillOpen();
  }
}

- (void)contextMenuDidClose {
  if (_owner) {
    _owner->OnMenuDidClose();
  }
}

- (void)contextMenuDidSelectItemWithID:(NSInteger)itemID {
  if (_owner) {
    _owner->OnItemSelected(itemID);
  }
}

@end

namespace fiber {

namespace {

// The items Fiber shows of Chrome's, and each one's symbol (empty for none).
// Chrome's others duplicate the window's controls or are Google services; new
// ones stay out until listed. macOS 27 doesn't draw images in context menus.
// TODO: autofill, passwords, and opening links in other profiles or web apps.
constexpr auto kShownCommands = base::MakeFixedFlatMap<int, std::string_view>({
    // A link.
    {IDC_CONTENT_CONTEXT_OPENLINKNEWTAB, "plus.square.on.square"},
    {IDC_CONTENT_CONTEXT_OPENLINKNEWWINDOW, "macwindow.badge.plus"},
    {IDC_CONTENT_CONTEXT_OPENLINKOFFTHERECORD, "hand.raised"},
    {IDC_CONTENT_CONTEXT_COPYLINKLOCATION, "link"},
    {IDC_CONTENT_CONTEXT_SAVELINKAS, "square.and.arrow.down"},
    // An image or canvas.
    {IDC_CONTENT_CONTEXT_LOAD_IMAGE, "photo"},
    {IDC_CONTENT_CONTEXT_OPENIMAGENEWTAB, "plus.square.on.square"},
    {IDC_CONTENT_CONTEXT_SAVEIMAGEAS, "square.and.arrow.down"},
    {IDC_CONTENT_CONTEXT_COPYIMAGE, "doc.on.doc"},
    {IDC_CONTENT_CONTEXT_COPYIMAGELOCATION, "link"},
    // Video or audio.
    {IDC_CONTENT_CONTEXT_LOOP, "repeat"},
    {IDC_CONTENT_CONTEXT_CONTROLS, "slider.horizontal.below.rectangle"},
    {IDC_CONTENT_CONTEXT_PICTUREINPICTURE, "pip.enter"},
    {IDC_CONTENT_CONTEXT_OPENAVNEWTAB, "plus.square.on.square"},
    {IDC_CONTENT_CONTEXT_SAVEAVAS, "square.and.arrow.down"},
    {IDC_CONTENT_CONTEXT_COPYAVLOCATION, "link"},
    // The video's current frame; a submenu of these in some layouts.
    {IDC_CONTENT_CONTEXT_VIDEO_FRAME, ""},
    {IDC_CONTENT_CONTEXT_COPYVIDEOFRAME, "doc.on.doc"},
    {IDC_CONTENT_CONTEXT_SAVEVIDEOFRAMEAS, "square.and.arrow.down"},
    // A plugin (a PDF).
    {IDC_CONTENT_CONTEXT_SAVEPLUGINAS, "square.and.arrow.down"},
    {IDC_CONTENT_CONTEXT_ROTATECW, "rotate.right"},
    {IDC_CONTENT_CONTEXT_ROTATECCW, "rotate.left"},
    // Selected text.
    {IDC_CONTENT_CONTEXT_COPY, "doc.on.doc"},
    {IDC_CONTENT_CONTEXT_COPYLINKTOTEXT, "link"},
    {IDC_CONTENT_CONTEXT_RESHARELINKTOTEXT, "link"},
    {IDC_CONTENT_CONTEXT_REMOVELINKTOTEXT, ""},
    {IDC_CONTENT_CONTEXT_SEARCHWEBFOR, "magnifyingglass"},
    {IDC_CONTENT_CONTEXT_GOTOURL, "globe"},
    {IDC_CONTENT_CONTEXT_LOOK_UP, "character.book.closed"},
    // Text being edited. Spelling suggestions are a range; see IsShown().
    {IDC_CONTENT_CONTEXT_NO_SPELLING_SUGGESTIONS, ""},
    {IDC_SPELLCHECK_ADD_TO_DICTIONARY, ""},
    {IDC_SPELLCHECK_REMOVE_FROM_DICTIONARY, ""},
    {IDC_CONTENT_CONTEXT_EMOJI, "face.smiling"},
    {IDC_CONTENT_CONTEXT_UNDO, "arrow.uturn.backward"},
    {IDC_CONTENT_CONTEXT_REDO, "arrow.uturn.forward"},
    {IDC_CONTENT_CONTEXT_CUT, "scissors"},
    {IDC_CONTENT_CONTEXT_PASTE, "doc.on.clipboard"},
    {IDC_CONTENT_CONTEXT_PASTE_AND_MATCH_STYLE, ""},
    {IDC_CONTENT_CONTEXT_SELECTALL, "selection.pin.in.out"},
    // A page that's fullscreen.
    {IDC_CONTENT_CONTEXT_EXIT_FULLSCREEN, "arrow.down.right.and.arrow.up.left"},
    // Developer tools.
    {IDC_VIEW_SOURCE, "chevron.left.forwardslash.chevron.right"},
    {IDC_CONTENT_CONTEXT_VIEWFRAMESOURCE,
     "chevron.left.forwardslash.chevron.right"},
    {IDC_CONTENT_CONTEXT_INSPECTELEMENT, "hammer"},
    {IDC_CONTENT_CONTEXT_INSPECTBACKGROUNDPAGE, "hammer"},
});

bool IsShown(int command_id) {
  return kShownCommands.contains(command_id) ||
         // What the page adds (a plugin, for example) and what extensions add.
         RenderViewContextMenuBase::IsContentCustomCommandId(command_id) ||
         extensions::ContextMenuMatcher::IsExtensionsCustomCommandId(
             command_id) ||
         // Spelling suggestions.
         (command_id >= IDC_SPELLCHECK_SUGGESTION_0 &&
          command_id < IDC_SPELLCHECK_LANGUAGES_FIRST) ||
         // macOS's Speech and Writing Direction submenus, and their items.
         (command_id >= ui::TextServicesContextMenu::kSpeechMenu &&
          command_id <= ui::TextServicesContextMenu::kWritingDirectionRtl);
}

NSString* SymbolName(int command_id) {
  auto it = kShownCommands.find(command_id);
  if (it == kShownCommands.end() || it->second.empty()) {
    return nil;
  }
  return base::SysUTF8ToNSString(it->second);
}

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

}  // namespace

FiberRenderViewContextMenu::FiberRenderViewContextMenu(
    content::RenderFrameHost& render_frame_host,
    const content::ContextMenuParams& params,
    bool is_paste_enabled,
    bool is_paste_and_match_style_enabled)
    : RenderViewContextMenuMac(render_frame_host,
                               params,
                               is_paste_enabled,
                               is_paste_and_match_style_enabled),
      actions_([[FiberRenderViewContextMenuActions alloc] initWithOwner:this]) {
}

FiberRenderViewContextMenu::~FiberRenderViewContextMenu() {
  [actions_ detachOwner];
  // Closes the menu if this goes while it's open (its tab closed, say).
  [menu_ cancel];
}

void FiberRenderViewContextMenu::Show() {
  content::RenderWidgetHostView* view =
      source_web_contents_->GetTopLevelRenderWidgetHostView();
  if (!view) {
    return;
  }
  NSArray<FiberContextMenuItem*>* items = ItemsFromModel(&menu_model_);
  if (items.count == 0) {
    return;
  }
  menu_ = [FiberContextMenuFactory menuWithItems:items actions:actions_];

  // At the click, as Chrome's own menu is; `params_` is in the page's top-level
  // view, flipped.
  NSView* parent_view = view->GetNativeView().GetNativeNSView();
  NSPoint position =
      NSMakePoint(params_.x, NSHeight(parent_view.bounds) - params_.y);
  position = [parent_view convertPoint:position toView:nil];
  NSEvent* event = ui::EventForPositioningContextMenuRelativeToWindow(
      position, parent_view.window);

  // Shown at the renderer's request, not from a user event, so this sets up
  // what AppKit's event tracking otherwise would: Chrome's tasks keep running,
  // and a window closing meanwhile waits until the event is done.
  base::CurrentThread::ScopedAllowApplicationTasksInNativeNestedLoop allow;
  base::mac::ScopedSendingEvent sending_event;
  // The menu can outlive this (see OnItemSelected()), so it's held here.
  id<FiberContextMenu> menu = menu_;
  [menu popUpWithEvent:event inView:parent_view];
}

void FiberRenderViewContextMenu::OnMenuWillOpen() {
  menu_model_.MenuWillShow();
}

void FiberRenderViewContextMenu::OnMenuDidClose() {
  // Tells Chrome's menu it closed, after any item chosen has run.
  menu_model_.MenuWillClose();
}

void FiberRenderViewContextMenu::OnItemSelected(NSInteger item_id) {
  if (item_id < 0 || static_cast<size_t>(item_id) >= items_.size()) {
    return;
  }
  const Item& item = items_[item_id];
  if (item.model) {
    // May delete this, for example by closing the tab.
    item.model->ActivatedAt(item.index,
                            ui::EventFlagsFromNative(base::apple::OwnedNSEvent(
                                NSApp.currentEvent)));
  }
}

void FiberRenderViewContextMenu::CancelToolkitMenu() {
  [menu_ cancel];
}

void FiberRenderViewContextMenu::UpdateToolkitMenuItem(
    int command_id,
    bool enabled,
    bool hidden,
    const std::u16string& title) {
  for (size_t item_id = 0; item_id < items_.size(); ++item_id) {
    const Item& item = items_[item_id];
    if (item.model && item.model->GetCommandIdAt(item.index) == command_id) {
      [menu_ updateItemWithID:item_id
                        title:base::SysUTF16ToNSString(title)
                      enabled:enabled
                       hidden:hidden];
      return;
    }
  }
}

NSArray<FiberContextMenuItem*>* FiberRenderViewContextMenu::ItemsFromModel(
    ui::MenuModel* model) {
  NSMutableArray<FiberContextMenuItem*>* items = [NSMutableArray array];
  // Separators only go between items that are shown, one at a time.
  bool separate = false;
  for (size_t index = 0; index < model->GetItemCount(); ++index) {
    if (!model->IsVisibleAt(index)) {
      continue;
    }
    const ui::MenuModel::ItemType type = model->GetTypeAt(index);
    if (type == ui::MenuModel::TYPE_SEPARATOR) {
      separate = items.count > 0;
      continue;
    }
    const int command_id = model->GetCommandIdAt(index);
    if (!IsShown(command_id)) {
      continue;
    }

    FiberContextMenuItemKind kind = FiberContextMenuItemKindCommand;
    NSArray<FiberContextMenuItem*>* submenu = @[];
    if (type == ui::MenuModel::TYPE_SUBMENU) {
      kind = FiberContextMenuItemKindSubmenu;
      submenu = ItemsFromModel(model->GetSubmenuModelAt(index));
      if (submenu.count == 0) {
        continue;
      }
    }

    if (separate) {
      [items addObject:Separator()];
      separate = false;
    }
    const std::u16string label = model->GetLabelAt(index);
    const NSInteger item_id = items_.size();
    items_.push_back({model->AsWeakPtr(), index});
    [items addObject:[[FiberContextMenuItem alloc]
                         initWithKind:kind
                               itemID:item_id
                                title:model->MayHaveMnemonicsAt(index)
                                          ? l10n_util::FixUpWindowsStyleLabel(
                                                label)
                                          : base::SysUTF16ToNSString(label)
                           symbolName:SymbolName(command_id)
                              enabled:model->IsEnabledAt(index)
                              checked:model->IsItemCheckedAt(index)
                              submenu:submenu]];
  }
  return items;
}

}  // namespace fiber
