#ifndef FIBER_BROWSER_FIBER_WINDOW_CONTROLLER_H_
#define FIBER_BROWSER_FIBER_WINDOW_CONTROLLER_H_

#import <Cocoa/Cocoa.h>

namespace fiber {
class FiberWindow;
}

// Owns a Fiber window's NSWindow and its native chrome (toolbar, load progress
// bar, link status bubble), and forwards UI events to the FiberWindow.
@interface FiberWindowController
    : NSObject <NSWindowDelegate,
                NSToolbarDelegate,
                NSTextFieldDelegate,
                NSUserInterfaceValidations>

@property(readonly, nonatomic) NSWindow* window;

- (instancetype)initWithOwner:(fiber::FiberWindow*)owner;
- (void)setWebContentsView:(NSView*)view;
// `url` is the full URL, shown while editing; `displayString` is the short
// form shown otherwise.
- (void)updateWithURL:(NSString*)url
        displayString:(NSString*)displayString
                title:(NSString*)title
            canGoBack:(BOOL)canGoBack
         canGoForward:(BOOL)canGoForward
            isLoading:(BOOL)isLoading;
// Shows the progress bar at `progress` (0 to 1) while `loading`, and completes
// and hides it once not.
- (void)setLoading:(BOOL)loading progress:(double)progress;
// Shows `text` (e.g. a hovered link's URL) in the bottom corner; empty hides it.
- (void)setStatusText:(NSString*)text;
- (void)focusLocationBar;
// Called by the owner when it is being destroyed.
- (void)detachOwner;

@end

#endif  // FIBER_BROWSER_FIBER_WINDOW_CONTROLLER_H_
