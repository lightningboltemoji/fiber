#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// What a window shows of its active tab's page: the toolbar's contents and the
// window title.
NS_SWIFT_SENDABLE
@interface FiberPageState : NSObject

- (instancetype)initWithURL:(NSString*)URL
                 displayURL:(NSString*)displayURL
                      title:(NSString*)title
                  canGoBack:(BOOL)canGoBack
               canGoForward:(BOOL)canGoForward
                    loading:(BOOL)loading NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

// The full URL, shown while the location field is being edited. Empty for
// pages that don't show their URL, like the New Tab page.
@property(readonly, copy) NSString* URL;
// A short form of the URL (usually just the host), shown otherwise.
@property(readonly, copy) NSString* displayURL;
@property(readonly, copy) NSString* title;
@property(readonly) BOOL canGoBack;
@property(readonly) BOOL canGoForward;
@property(readonly) BOOL isLoading;

@end

NS_ASSUME_NONNULL_END
