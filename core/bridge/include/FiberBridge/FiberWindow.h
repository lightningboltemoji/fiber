#import <AppKit/AppKit.h>

@class FiberPageState;
@class FiberTabState;
@protocol FiberExtensions;
@protocol FiberOmnibox;

NS_ASSUME_NONNULL_BEGIN

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
// Does nothing if the tab is gone.
- (void)selectTabWithID:(NSInteger)tabID;

// The user asked to close the window. The browser closes it when it's ready,
// which may be never: a page's unload handler can keep it open.
- (void)windowShouldClose;
- (void)windowDidBecomeMain;
- (void)windowDidResignMain;
- (void)windowDidChangeFullScreen;

@end

// //fiber/browser shows and positions `window`, which handles
// -toggleToolbarShown: (Show Toolbar in the View menu) itself.
NS_SWIFT_UI_ACTOR
@protocol FiberWindow <NSObject>

@property(readonly) NSWindow* window;
// The command palette, where the user enters an address or search.
@property(readonly) id<FiberOmnibox> omnibox;
@property(readonly) id<FiberExtensions> extensions;

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
// window. The window isn't shown until its owner orders it front.
+ (id<FiberWindow>)windowWithFrame:(NSRect)frame
                           actions:(id<FiberWindowActions>)actions;

- (instancetype)init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
