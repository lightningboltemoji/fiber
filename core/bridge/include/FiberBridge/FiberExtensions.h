#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

// What the toolbar and the extensions menu show of an extension: its button
// (its action), as it is for the window's active tab.
NS_SWIFT_SENDABLE
@interface FiberExtensionState : NSObject

- (instancetype)initWithExtensionID:(NSString*)extensionID
                               name:(NSString*)name
                            tooltip:(NSString*)tooltip
                               icon:(nullable NSImage*)icon
                          badgeText:(NSString*)badgeText
                     badgeTextColor:(nullable NSColor*)badgeTextColor
               badgeBackgroundColor:(nullable NSColor*)badgeBackgroundColor
                            enabled:(BOOL)enabled
                             pinned:(BOOL)pinned
                       canTogglePin:(BOOL)canTogglePin
    NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

// Identifies the extension for as long as it's installed.
@property(readonly, copy) NSString* extensionID;
@property(readonly, copy) NSString* name;
// What the extension says its button does here, or else its name.
@property(readonly, copy) NSString* tooltip;
// Without the badge. Nil while it loads.
@property(readonly, nullable) NSImage* icon;
// A few characters over the icon's corner, like a count. Empty for none.
@property(readonly, copy) NSString* badgeText;
// Nil for the default.
@property(readonly, nullable) NSColor* badgeTextColor;
@property(readonly, nullable) NSColor* badgeBackgroundColor;
// Whether its button does anything on this page. If not, it's dimmed, and
// clicking it shows its menu instead.
@property(readonly) BOOL isEnabled;
// Whether its button stays in the toolbar, beside the extensions menu's.
@property(readonly) BOOL isPinned;
// Whether the user can pin or unpin it: not if it's pinned by policy, nor in
// an Incognito window.
@property(readonly) BOOL canTogglePin;

@end

// What the user does with a window's extensions.
NS_SWIFT_UI_ACTOR
@protocol FiberExtensionsActions <NSObject>

// The user clicked the extension's button, in the toolbar or the extensions
// menu. It does what the extension says, usually opening its popup (see
// -[FiberExtensions popupForExtensionWithID:contentsView:actions:]).
- (void)runExtensionWithID:(NSString*)extensionID fromMenu:(BOOL)fromMenu;
- (void)setPinned:(BOOL)pinned forExtensionWithID:(NSString*)extensionID;
// Shows the extension's menu (Options, Unpin, Remove…) at `event`'s location
// in `view`, and returns once it closes.
- (void)showMenuForExtensionWithID:(NSString*)extensionID
                             event:(NSEvent*)event
                              view:(NSView*)view;
// Opens the Extensions page.
- (void)manageExtensions;

@end

// How an extension's popup ended.
NS_SWIFT_UI_ACTOR
@protocol FiberExtensionPopupActions <NSObject>

// The popup closed without -close: the user clicked away from it, or its
// window closed.
- (void)extensionPopupDidClose;

@end

// An extension's popup: its page, in a panel from its button.
NS_SWIFT_UI_ACTOR
@protocol FiberExtensionPopup <NSObject>

// The page's size, which the popup fits.
- (void)setContentSize:(NSSize)size;
// Shows the popup, once its page has loaded.
- (void)show;
// Closes the popup. Its actions get nothing more.
- (void)close;

@end

// A window's extensions: the extensions menu, and the buttons of those pinned
// beside it, in the toolbar.
NS_SWIFT_UI_ACTOR
@protocol FiberExtensions <NSObject>

// Set once, before anything's shown.
@property(nonatomic, nullable) id<FiberExtensionsActions> actions;

// Replaces the extensions. The menu lists them in `extensions`' order; the
// toolbar shows those in `pinnedIDs`, in its order.
- (void)setExtensions:(NSArray<FiberExtensionState*>*)extensions
            pinnedIDs:(NSArray<NSString*>*)pinnedIDs;
// Opens the extensions menu, or closes it if it's open.
- (void)toggleMenu;
- (void)closeMenu;
// Shows the extension's menu as if its button were right-clicked.
- (void)showMenuForExtensionWithID:(NSString*)extensionID;
// A popup showing `contentsView`, the extension's page, from its button, or
// from the extensions menu's if it isn't pinned. It closes any other popup,
// and isn't shown until -show.
- (id<FiberExtensionPopup>)
    popupForExtensionWithID:(NSString*)extensionID
               contentsView:(NSView*)contentsView
                    actions:(id<FiberExtensionPopupActions>)actions;

@end

NS_ASSUME_NONNULL_END
