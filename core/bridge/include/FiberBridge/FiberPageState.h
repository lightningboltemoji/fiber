#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// What a window shows of its active tab's page: the toolbar's controls and the
// window title.
NS_SWIFT_SENDABLE
@interface FiberPageState : NSObject

- (instancetype)initWithURL:(NSString*)URL
                 displayURL:(NSString*)displayURL
                      title:(NSString*)title
                  canGoBack:(BOOL)canGoBack
               canGoForward:(BOOL)canGoForward
                    loading:(BOOL)loading
                 newTabPage:(BOOL)newTabPage NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

// The full URL, which the command palette opens with. Empty for pages that
// don't show their URL, like the New Tab page.
@property(readonly, copy) NSString* URL;
// A short form of the URL (usually just the host), shown in the toolbar.
@property(readonly, copy) NSString* displayURL;
@property(readonly, copy) NSString* title;
@property(readonly) BOOL canGoBack;
@property(readonly) BOOL canGoForward;
@property(readonly) BOOL isLoading;
// Chrome's New Tab page, which the window covers with its own.
@property(readonly) BOOL isNewTabPage;

@end

NS_ASSUME_NONNULL_END
