#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

// What a window shows of its active tab's page: the toolbar's controls, the
// window title, and the tab stack beside the page.
NS_SWIFT_SENDABLE
@interface FiberPageState : NSObject

- (instancetype)initWithDisplayURL:(NSString*)displayURL
                             title:(NSString*)title
                         canGoBack:(BOOL)canGoBack
                      canGoForward:(BOOL)canGoForward
                           loading:(BOOL)loading
                        newTabPage:(BOOL)newTabPage
                   backgroundColor:(nullable NSColor*)backgroundColor
    NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

// A short form of the URL (usually just the host), shown in the toolbar. Empty
// for pages that don't show their URL, like the New Tab page.
@property(readonly, copy) NSString* displayURL;
@property(readonly, copy) NSString* title;
@property(readonly) BOOL canGoBack;
@property(readonly) BOOL canGoForward;
@property(readonly) BOOL isLoading;
// Fiber's New Tab page (chrome://newtab), which the window draws.
@property(readonly) BOOL isNewTabPage;
// The page's background color, as its CSS sets it, if it has one. The tab
// stack takes its colors from it.
@property(readonly, nullable) NSColor* backgroundColor;

@end

NS_ASSUME_NONNULL_END
