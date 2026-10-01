#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

// One of the profile's pins: a page the user pinned to come back to, which
// every window shows, and opens in a tab of its own when it's clicked.
NS_SWIFT_SENDABLE
@interface FiberPinState : NSObject

- (instancetype)initWithID:(NSString*)pinID
                     title:(NSString*)title
                       url:(NSString*)url
                   favicon:(nullable NSImage*)favicon
                     tabID:(NSInteger)tabID
                   loading:(BOOL)loading
               atPinnedURL:(BOOL)atPinnedURL NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@property(readonly, copy) NSString* pinID;
@property(readonly, copy) NSString* title;
// The URL it opens, formatted to read.
@property(readonly, copy) NSString* url;
// Its tab's favicon while it's open, otherwise the one its page last had.
@property(readonly, nullable) NSImage* favicon;
// Its tab in this window (see FiberTabState), or 0 if it isn't open here.
@property(readonly) NSInteger tabID;
@property(readonly) BOOL isLoading;
// Whether its tab is on the URL it opens. NO if it isn't open here.
@property(readonly) BOOL isAtPinnedURL;

@end

NS_ASSUME_NONNULL_END
