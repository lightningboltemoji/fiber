#import <AppKit/AppKit.h>

@class FiberPageState;
@class FiberTabState;
@protocol FiberExtensions;
@protocol FiberOmnibox;
@protocol FiberTabIndex;

NS_ASSUME_NONNULL_BEGIN

// Browser commands the command palette lists.
typedef NS_ENUM(NSInteger, FiberCommand) {
  FiberCommandNewTab,
  // Prints the active tab's page, with the system's print panel.
  FiberCommandPrint,
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
// The active tab's sad tab (see FiberSadTab): its button, and its help link.
- (void)pressSadTabButton;
- (void)openSadTabHelp;
// Selects the tab, in whichever of the profile's windows has it, and brings
// that window forward. Does nothing if the tab is gone.
- (void)selectTabWithID:(NSInteger)tabID;
// Selects the tab, as -selectTabWithID: does, and finds `text` (from its page
// text, see FiberTabIndex) in its page, leaving it selected.
- (void)revealText:(NSString*)text inTabWithID:(NSInteger)tabID;
// Closes one of the window's tabs, as its close button would: the page may
// ask the user first.
- (void)closeTabWithID:(NSInteger)tabID;
- (BOOL)canRunCommand:(FiberCommand)command;
- (void)runCommand:(FiberCommand)command;
// The command palette opened. The active tab's page text may have changed
// since it was last read.
- (void)commandPaletteDidOpen;

// The user asked to close the window. The browser closes it when it's ready,
// which may be never: a page's unload handler can keep it open.
- (void)windowShouldClose;
- (void)windowDidBecomeMain;
- (void)windowDidResignMain;
- (void)windowDidChangeFullScreen;

@end

// Main menu actions a window handles itself.
NS_SWIFT_UI_ACTOR
@protocol FiberWindowMenuActions <NSObject>

// Opens the command palette, or closes it if it's open.
- (void)toggleCommandPalette:(nullable id)sender;

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
- (void)setPageState:(FiberPageState*)state;
// Replaces the tab list with `tabs`, in order. `activeTabID` is the tab whose
// page is in the content area.
- (void)setTabs:(NSArray<FiberTabState*>*)tabs
    activeTabID:(NSInteger)activeTabID;
// Shows the page's load progress (0 to 1) while `loading`, and completes and
// hides it once not.
- (void)setLoading:(BOOL)loading progress:(double)progress;
// Shows `text` (for example a hovered link's URL) in the window's bottom
// corner. Empty hides it.
- (void)setStatusText:(NSString*)text;
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
// exists: the New Tab page with the omnibar open, as a browser usually starts,
// when `newTabPage`, or else an empty page. The first browser takes it over,
// and tells it what to show from then on. It isn't Incognito.
+ (id<FiberWindow>)startupWindowWithFrame:(NSRect)frame
                               newTabPage:(BOOL)newTabPage;

- (instancetype)init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
