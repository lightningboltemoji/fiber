#import <Foundation/Foundation.h>

@class FiberTabState;

NS_ASSUME_NONNULL_BEGIN

// What the command palette searches in one profile: its tabs, in all of its
// windows, and the text of their pages. The profile's windows share it.
NS_SWIFT_UI_ACTOR
@protocol FiberTabIndex <NSObject>

// Replaces the tabs, in any order.
- (void)setTabs:(NSArray<FiberTabState*>*)tabs;
// The text of the tab's page, as last read: its inner text, a line per block.
// Empty when the page has none, or has changed since. It's dropped when the
// tab is.
- (void)setPageText:(NSString*)text forTabWithID:(NSInteger)tabID;

@end

NS_SWIFT_UI_ACTOR
@interface FiberTabIndexFactory : NSObject

+ (id<FiberTabIndex>)tabIndex;

- (instancetype)init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
