#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, FiberContextMenuItemKind) {
  // Does something when chosen.
  FiberContextMenuItemKindCommand,
  // Opens its submenu.
  FiberContextMenuItemKindSubmenu,
  // A line between groups of items. Has no ID or title.
  FiberContextMenuItemKindSeparator,
};

// One item in a page's context menu.
NS_SWIFT_SENDABLE
@interface FiberContextMenuItem : NSObject

- (instancetype)initWithKind:(FiberContextMenuItemKind)kind
                      itemID:(NSInteger)itemID
                       title:(NSString*)title
                  symbolName:(nullable NSString*)symbolName
                     enabled:(BOOL)enabled
                     checked:(BOOL)checked
                     submenu:(NSArray<FiberContextMenuItem*>*)submenu
    NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@property(readonly) FiberContextMenuItemKind kind;
// Identifies the item to its menu's actions, and in updates. Unique within
// the menu, submenus included.
@property(readonly) NSInteger itemID;
@property(readonly, copy) NSString* title;
// The SF Symbol shown beside the title, if any.
@property(readonly, copy, nullable) NSString* symbolName;
@property(readonly) BOOL enabled;
// Shows a checkmark.
@property(readonly) BOOL checked;
// A submenu's items. Empty for other kinds.
@property(readonly, copy) NSArray<FiberContextMenuItem*>* submenu;

@end

// What the user does with a context menu.
NS_SWIFT_UI_ACTOR
@protocol FiberContextMenuActions <NSObject>

- (void)contextMenuWillOpen;
// Called once, however the menu closed. If the user chose an item,
// -contextMenuDidSelectItemWithID: may come before or after this.
- (void)contextMenuDidClose;
// The user chose the command with this ID.
- (void)contextMenuDidSelectItemWithID:(NSInteger)itemID;

@end

// A context menu for something on a page (a link, an image, selected text…).
NS_SWIFT_UI_ACTOR
@protocol FiberContextMenu <NSObject>

// Shows the menu at `event`'s location in `view`, and returns once it closes.
// The event loop keeps running meanwhile, so anything can happen before this
// returns, including the menu's owner going away.
- (void)popUpWithEvent:(NSEvent*)event inView:(NSView*)view;
// Changes an item while the menu is open, for items whose state is only known
// after it opens (a spelling suggestion that's still loading, say). Does
// nothing if no item has this ID.
- (void)updateItemWithID:(NSInteger)itemID
                   title:(NSString*)title
                 enabled:(BOOL)enabled
                  hidden:(BOOL)hidden;
// Closes the menu if it's open.
- (void)cancel;

@end

NS_SWIFT_UI_ACTOR
@interface FiberContextMenuFactory : NSObject

+ (id<FiberContextMenu>)menuWithItems:(NSArray<FiberContextMenuItem*>*)items
                              actions:(id<FiberContextMenuActions>)actions;

- (instancetype)init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
