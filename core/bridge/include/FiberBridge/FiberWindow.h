#import <AppKit/AppKit.h>

@class FiberPageState;
@class FiberTabState;
@protocol FiberOmnibox;

NS_ASSUME_NONNULL_BEGIN

// What happens in a browser window that the browser acts on.
//
// Calls that open a page take the event that triggered them, if any. Its
// modifier keys decide where the page opens; for example, Command-clicking
// Back opens the previous page in a new tab.
//
// The window also forwards menu actions that nothing in its responder chain
// handles to this object (when it responds to them), so the main menu acts on
// the key window's browser.
NS_SWIFT_UI_ACTOR
@protocol FiberWindowActions <NSObject>

- (void)goBackWithEvent:(nullable NSEvent*)event;
- (void)goForwardWithEvent:(nullable NSEvent*)event;
- (void)reloadWithEvent:(nullable NSEvent*)event;
- (void)stopLoading;
// Moves keyboard focus to the page.
- (void)focusPage;
// Makes the tab with this ID the active one. Does nothing if it's gone.
- (void)selectTabWithID:(NSInteger)tabID;

// The user asked to close the window. The browser closes it when it's ready,
// which may be never: a page's unload handler can keep it open.
- (void)windowShouldClose;
- (void)windowDidBecomeMain;
- (void)windowDidResignMain;
- (void)windowDidChangeFullScreen;

@end

// A browser window. Its owner in //fiber/browser shows and positions
// `window`, and tells it what to display.
//
// `window` handles -toggleToolbarShown: (Show Toolbar in the View menu), which
// shows or hides its toolbar.
NS_SWIFT_UI_ACTOR
@protocol FiberWindow <NSObject>

@property(readonly) NSWindow* window;
// The command palette, where the user enters an address or search.
@property(readonly) id<FiberOmnibox> omnibox;

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
