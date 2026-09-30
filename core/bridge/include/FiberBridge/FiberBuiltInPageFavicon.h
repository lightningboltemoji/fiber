#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

// The favicons of the browser's built-in pages (chrome://settings and the
// like), which Fiber picks for every one of them.
NS_SWIFT_UI_ACTOR
@interface FiberBuiltInPageFavicon : NSObject

// The favicon of the built-in page at `host` ("newtab", "settings"…), a PNG
// `pixelSize` pixels square in one gray. Fiber's UI draws it as a template.
+ (NSData*)pngForHost:(NSString*)host pixelSize:(NSInteger)pixelSize;

- (instancetype)init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
