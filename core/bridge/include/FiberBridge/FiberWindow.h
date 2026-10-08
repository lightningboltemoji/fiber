#import <AppKit/AppKit.h>

@class FiberDevTools;
@class FiberPageState;
@class FiberPinState;
@class FiberTabState;
@protocol FiberDownloads;
@protocol FiberExtensions;
@protocol FiberFindBar;
@protocol FiberOmnibox;
@protocol FiberTabIndex;

NS_ASSUME_NONNULL_BEGIN

// Browser commands the command palette lists.
typedef NS_ENUM(NSInteger, FiberCommand) {
  FiberCommandNewTab,
  // Prints the active tab's page, with the system's print panel.
  FiberCommandPrint,
  // Lets the active tab's page and its DevTools have Command-S, Command-P and
  // Command-L until the user ends it or the tab goes to another site.
  FiberCommandKeyPassthrough,
};

typedef NS_ENUM(NSInteger, FiberHistorySwipeDirection) {
  // To the previous page: the page moves right, uncovering it.
  FiberHistorySwipeDirectionBack,
  // To the next page, which slides in from the right over this one.
  FiberHistorySwipeDirectionForward,
};

// Calls that open a page take the event behind them, if any, whose modifiers
// decide where it opens. Menu actions nothing in the window's responder chain
// handles come here too, so the main menu acts on the key window's browser.
NS_SWIFT_UI_ACTOR
@protocol FiberWindowActions <NSObject>

- (void)goBackWithEvent:(nullable NSEvent*)event;
- (void)goForwardWithEvent:(nullable NSEvent*)event;
- (void)reloadWithEvent:(nullable NSEvent*)event;
- (void)stopLoading;
- (void)focusPage;
// Focuses the active tab as switching to it does: its page, or the omnibar on
// a New Tab page.
- (void)restoreFocus;
// The active tab's sad tab (see FiberSadTab): its button, and its help link.
- (void)pressSadTabButton;
- (void)openSadTabHelp;
// Selects the tab, in whichever of the profile's windows has it, and brings
// that window forward. Does nothing if the tab is gone.
- (void)selectTabWithID:(NSInteger)tabID;
// Selects the tab, as -selectTabWithID: does, and finds `text` (from its page
// text, see FiberTabIndex) in its page, leaving it selected.
- (void)revealText:(NSString*)text inTabWithID:(NSInteger)tabID;
// Brings back a window the user closed, or an earlier session's windows (see
// FiberTabIndex), as they were, but showing page `pageIndex` of a closed
// window's if it isn't NSNotFound.
- (void)restore:(NSString*)restorableID showingPageAtIndex:(NSInteger)pageIndex;
// Closes one of the window's tabs, as its close button would: the page may
// ask the user first.
- (void)closeTabWithID:(NSInteger)tabID;
// Pins the tab's page (see FiberPinState): the tab becomes its pin's.
- (void)pinTabWithID:(NSInteger)tabID;
// Selects the pin's tab, or opens its URL in a new one.
- (void)openPinWithID:(NSString*)pinID;
// The pin's tab goes back to the URL the pin opens.
- (void)resetPinWithID:(NSString*)pinID;
// The pin opens the page its tab is on from now on.
- (void)updateURLOfPinWithID:(NSString*)pinID;
// Unpins the page, from every window. Its tabs stay, as ordinary tabs.
- (void)unpinPinWithID:(NSString*)pinID;
// Moves the pin to `index` among the pins, in every window.
- (void)movePinWithID:(NSString*)pinID toIndex:(NSInteger)index;
- (BOOL)canRunCommand:(FiberCommand)command;
- (void)runCommand:(FiberCommand)command;
- (void)endKeyPassthrough;
// The window offers each key equivalent here before its views see it. While
// web content has focus, runs the shortcuts pages don't get (Chrome's reserved
// ones, and Fiber's unless the tab has key passthrough) and returns YES.
- (BOOL)performReservedKeyEquivalent:(NSEvent*)event;
// The command palette opened. The active tab's page text may have changed
// since it was last read.
- (void)commandPaletteDidOpen;
// Calls `completion` with a small image of what the active tab's page shows
// now, for the window to see how light it is, or with nil if it hasn't drawn.
- (void)capturePageThumbnail:
    (void (^)(CGImageRef _Nullable thumbnail))completion;

// The user asked to close the window. The browser closes it when it's ready,
// which may be never: a page's unload handler can keep it open.
- (void)windowShouldClose;
- (void)windowDidBecomeMain;
- (void)windowDidResignMain;
- (void)windowDidChangeFullScreen;
// The window moved or changed size (once a live resize is over): the browser
// keeps where it is, for restoring it.
- (void)windowDidChangeFrame;

@end

// Main menu actions a window handles itself.
NS_SWIFT_UI_ACTOR
@protocol FiberWindowMenuActions <NSObject>

// Opens the command palette, or closes it if it's open.
- (void)toggleCommandPalette:(nullable id)sender;
// Starts or ends the active tab's key passthrough.
- (void)toggleKeyPassthrough:(nullable id)sender;

@end

// //fiber/browser shows and positions `window`, which handles
// -toggleToolbarShown: (Show Toolbar in the View menu) and
// FiberWindowMenuActions itself.
NS_SWIFT_UI_ACTOR
@protocol FiberWindow <NSObject>

@property(readonly) NSWindow* window;
// The omnibar, where the user enters an address or search.
@property(readonly) id<FiberOmnibox> omnibox;
@property(readonly) id<FiberExtensions> extensions;
// Listed in the tab overlay, under its tabs.
@property(readonly) id<FiberDownloads> downloads;
@property(readonly) id<FiberFindBar> findBar;
// A startup window's are set once, by the browser that takes it over (see
// FiberWindowFactory); what the user does before then waits in the event
// queue, since the browser starts up on the main thread.
@property(nonatomic, nullable) id<FiberWindowActions> actions;
@property(nonatomic, nullable) id<FiberTabIndex> tabIndex;

// Opens the command palette, which searches the profile's tabs and runs
// commands. If it's open, its text is selected.
- (void)showCommandPalette;

// Shows `view` (the active tab's page) in the content area in place of the
// previous one. Nil leaves the content area empty.
- (void)setContentsView:(nullable NSView*)view;
// Shows the active tab's DevTools with its page, or with nil, the page alone.
// The window's controls lay out over the page as if it were the window, and
// hide while it emulates a device.
- (void)setDevTools:(nullable FiberDevTools*)devTools;
- (void)setPageState:(FiberPageState*)state;
// Shows a startup window's page, which until then doesn't show (see
// startupWindowWithFrame:).
- (void)showPage;
// Replaces the tab list with `tabs`, in order. `activeTabID` is the tab whose
// page is in the content area.
- (void)setTabs:(NSArray<FiberTabState*>*)tabs
    activeTabID:(NSInteger)activeTabID;
// `tabID` was just opened from `openerTabID`, the active tab, by a link on its
// page, an extension, or the omnibar: behind it, or in front of it, so that
// `tabID` is active now. Not called for a New Tab page. Follows the
// -setTabs:activeTabID: that lists it.
- (void)didOpenTabWithID:(NSInteger)tabID fromTabWithID:(NSInteger)openerTabID;
// Replaces the pins with `pins`, in order. Their open tabs are among the tabs
// too. Never called for a window that can't have pins, like an Incognito one.
- (void)setPins:(NSArray<FiberPinState*>*)pins;
// Shows the page's load progress (0 to 1) while `loading`, and completes and
// hides it once not.
- (void)setLoading:(BOOL)loading progress:(double)progress;
// Shows `text`, a hovered link's URL or the page's load status, in the
// page's bottom corner. Empty hides it after a moment, for the pointer to
// reach the next link.
- (void)setStatusText:(NSString*)text;
// Hides the status text at once, as the page navigates or another tab's shows.
- (void)hideStatusText;
// The pointer moved over the page or off it. The status text keeps clear of
// it.
- (void)pointerMovedOverPage;
// The toolbar and tab picker are hidden while a page is fullscreen, for
// example a video.
- (void)setControlsVisible:(BOOL)visible;

// Swiping between pages (two fingers on a trackpad, one on a mouse): the page
// follows the user's fingers, with `snapshot`, what the page it's going to
// last looked like, beside it; nil shows the window's background instead.
- (void)beginHistorySwipeInDirection:(FiberHistorySwipeDirection)direction
                            snapshot:(nullable NSImage*)snapshot;
// How far the user's fingers have taken the swipe, from 0 to 1 (the page
// it's going to showing whole).
- (void)updateHistorySwipe:(double)progress;
// The user let go. The swipe decides from where it is and how fast it was
// going whether it lands on the other page, carries itself there or back,
// and then calls `completion` with whether it landed.
- (void)releaseHistorySwipe:(void (^)(BOOL landed))completion;
// The swipe is over. If `navigating`, the page is going back or forward, and
// the snapshot covers it until -finishHistorySwipeNavigation; otherwise it's
// back as it was.
- (void)endHistorySwipeNavigating:(BOOL)navigating;
// The page swiped to is showing (or isn't coming): the snapshot goes.
- (void)finishHistorySwipeNavigation;
@end

NS_SWIFT_UI_ACTOR
@interface FiberWindowFactory : NSObject

// `frame` is in screen coordinates; an empty frame centers a default-sized
// window. The window isn't shown until its owner orders it front. `tabIndex`
// is its profile's. An `incognito` window's profile keeps no history, and its
// cookies and site data go with its last window.
+ (id<FiberWindow>)windowWithFrame:(NSRect)frame
                           actions:(id<FiberWindowActions>)actions
                          tabIndex:(id<FiberTabIndex>)tabIndex
                         incognito:(BOOL)incognito;

// A window for the browser that's starting up, to show before the browser
// exists. The first browser takes it over and tells it what to show, but its
// page, and the omnibar over it, don't show until showPage. It isn't
// Incognito.
+ (id<FiberWindow>)startupWindowWithFrame:(NSRect)frame;

- (instancetype)init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
