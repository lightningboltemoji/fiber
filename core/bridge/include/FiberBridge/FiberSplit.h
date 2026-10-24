#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

// Two of the window's tabs side by side: on the right the one the user keeps
// there, and on the left whichever else they go to, a pin's or a shelf
// page's too. A pin's is never on the right.
NS_SWIFT_UI_ACTOR
@interface FiberSplit : NSObject

- (instancetype)initWithLeftTabID:(NSInteger)leftTabID
                       rightTabID:(NSInteger)rightTabID
                            ratio:(double)ratio
                        otherView:(nullable NSView*)otherView
                otherIsNewTabPage:(BOOL)otherIsNewTabPage
    NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@property(readonly) NSInteger leftTabID;
@property(readonly) NSInteger rightTabID;
// The left tab's share of the page's width, from 0 to 1.
@property(readonly) double ratio;
// While the active tab is one of the two, the other's page, shown beside it.
// Otherwise nil, and the active tab's page shows alone.
@property(readonly, nullable) NSView* otherView;
// Whether the other is on Fiber's New Tab page, which the window draws.
@property(readonly) BOOL otherIsNewTabPage;

@end

NS_ASSUME_NONNULL_END
