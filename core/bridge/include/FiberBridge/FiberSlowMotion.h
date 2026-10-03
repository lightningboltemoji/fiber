#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

// Plays the UI's animations slower, for watching them closely.
NS_SWIFT_UI_ACTOR
@interface FiberSlowMotion : NSObject

// How many times longer animations take: 1, as normal, or more. Animations
// already running keep their speed.
@property(class) double factor;

- (instancetype)init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
