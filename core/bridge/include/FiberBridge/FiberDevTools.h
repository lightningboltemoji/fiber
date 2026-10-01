#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, FiberDevToolsDock) {
  // Along the window's bottom edge, under the page.
  FiberDevToolsDockBottom,
  // Along the window's right edge, beside the page.
  FiberDevToolsDockRight,
  // In a window of their own; what's under the page is device emulation's
  // controls, whose frame fills the content area.
  FiberDevToolsDockUndocked,
};

// The DevTools a window shows with its active tab's page: a page of DevTools'
// own that fills the content area, with the tab's page over it, where DevTools
// puts it. DevTools draws the splitter beside the page, and moves it.
NS_SWIFT_UI_ACTOR
@interface FiberDevTools : NSObject

- (instancetype)initWithView:(NSView*)view
                        dock:(FiberDevToolsDock)dock
                   pageFrame:(NSRect)pageFrame
              emulatesDevice:(BOOL)emulatesDevice NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@property(readonly) NSView* view;
@property(readonly) FiberDevToolsDock dock;
// In `view`, measured from its top-left corner. Empty until DevTools first
// says, and the page fills `view` meanwhile.
@property(readonly) NSRect pageFrame;
// The page is an emulated device's screen, inside DevTools' controls, rather
// than all of the content area that isn't DevTools.
@property(readonly) BOOL emulatesDevice;

@end

NS_ASSUME_NONNULL_END
