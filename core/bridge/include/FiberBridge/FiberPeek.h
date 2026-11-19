#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

// A page a link opened over the tab it came from, the lower tab: its card
// over that tab's page, which shows around it, blurred, until the user closes
// it or expands it into a tab of its own. The tab overlay shows the two as the
// lower tab.
NS_SWIFT_UI_ACTOR
@interface FiberPeek : NSObject

- (instancetype)initWithLowerTabID:(NSInteger)lowerTabID
                         peekTabID:(NSInteger)peekTabID
                         lowerView:(nullable NSView*)lowerView
                          peekView:(nullable NSView*)peekView
    NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@property(readonly) NSInteger lowerTabID;
@property(readonly) NSInteger peekTabID;
// While the active tab is one of the two, their pages. Otherwise nil, and
// neither shows.
@property(readonly, nullable) NSView* lowerView;
@property(readonly, nullable) NSView* peekView;

@end

NS_ASSUME_NONNULL_END
