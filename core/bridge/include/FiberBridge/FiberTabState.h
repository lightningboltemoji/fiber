#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

// One of the browser's tabs, as the tab lists and the command palette show it.
NS_SWIFT_SENDABLE
@interface FiberTabState : NSObject

- (instancetype)initWithID:(NSInteger)tabID
                     title:(NSString*)title
                       url:(NSString*)url
                   favicon:(nullable NSImage*)favicon
                   loading:(BOOL)loading
            lastActiveTime:(NSDate*)lastActiveTime NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

// Identifies the tab for as long as it exists, wherever it moves.
@property(readonly) NSInteger tabID;
@property(readonly, copy) NSString* title;
// The page's URL, formatted to read: a Unicode host, and no "https://".
@property(readonly, copy) NSString* url;
@property(readonly, nullable) NSImage* favicon;
@property(readonly) BOOL isLoading;
// When the tab was last shown, or opened.
@property(readonly, copy) NSDate* lastActiveTime;

@end

NS_ASSUME_NONNULL_END
