#import <AppKit/AppKit.h>

@class FiberPageState;

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
// Opens what the user entered in the location field: a URL, or a search.
- (void)navigateToInput:(NSString*)input event:(nullable NSEvent*)event;
// Moves keyboard focus to the page.
- (void)focusPage;

// The user asked to close the window. The browser closes it when it's ready,
// which may be never: a page's unload handler can keep it open.
- (void)windowShouldClose;
- (void)windowDidBecomeMain;
- (void)windowDidResignMain;
- (void)windowDidChangeFullScreen;

@end

// A browser window. Its owner in //fiber/browser shows and positions
// `window`, and tells it what to display.
NS_SWIFT_UI_ACTOR
@protocol FiberWindow <NSObject>

@property(readonly) NSWindow* window;

// Shows `view` (the active tab's page) in the content area in place of the
// previous one. Nil leaves the content area empty.
- (void)setContentsView:(nullable NSView*)view;
- (void)setPageState:(FiberPageState*)state;
// Shows the page's load progress (0 to 1) while `loading`, and completes and
// hides it once not.
- (void)setLoading:(BOOL)loading progress:(double)progress;
// Shows `text` (for example a hovered link's URL) in the window's bottom
// corner. Empty hides it.
- (void)setStatusText:(NSString*)text;
// The toolbar is hidden while a page is fullscreen, for example a video.
- (void)setToolbarVisible:(BOOL)visible;
- (void)focusLocationBar;

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
