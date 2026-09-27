#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

// Holding the quit shortcut to quit, when Warn Before Quitting is on. The
// browser windows' pages blur and darken while the user holds it, and the
// windows fade out once they've held it long enough.
NS_SWIFT_UI_ACTOR
@interface FiberQuitConfirmation : NSObject

// Called as the quit shortcut goes down, with its key-down `event`. Returns
// once the user lets go: YES if they held it long enough, or pressed it again
// soon after letting go early, with the windows faded out; NO otherwise.
// VoiceOver reads `announcement`, which says what to do.
+ (BOOL)runWithEvent:(NSEvent*)event announcement:(NSString*)announcement;

// The quit didn't happen after all (a page kept its window open, say): brings
// the windows back.
+ (void)restoreWindows;

- (instancetype)init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
