#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

// What a window's tab list shows of one of its tabs.
NS_SWIFT_SENDABLE
@interface FiberTabState : NSObject

- (instancetype)initWithID:(NSInteger)tabID
                     title:(NSString*)title
                   favicon:(nullable NSImage*)favicon
                   loading:(BOOL)loading NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

// Identifies the tab for as long as it exists, wherever it moves.
@property(readonly) NSInteger tabID;
@property(readonly, copy) NSString* title;
// Nil while the page has no favicon (yet).
@property(readonly, nullable) NSImage* favicon;
@property(readonly) BOOL isLoading;

@end

NS_ASSUME_NONNULL_END
