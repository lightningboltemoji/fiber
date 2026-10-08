#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, FiberRestorableKind) {
  // A window the user closed.
  FiberRestorableKindWindow,
  // The windows open as an earlier session ended (Fiber quit or crashed),
  // which aren't all open again now.
  FiberRestorableKindSession,
};

// One of a restorable's tabs, by the page it was on.
NS_SWIFT_SENDABLE
@interface FiberRestorablePage : NSObject

- (instancetype)initWithTitle:(NSString*)title
                          url:(NSString*)url NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@property(readonly, copy) NSString* title;
// Formatted to read, as FiberTabState's is.
@property(readonly, copy) NSString* url;

@end

// Windows the command palette can bring back (see FiberTabIndex).
NS_SWIFT_SENDABLE
@interface FiberRestorable : NSObject

- (instancetype)initWithID:(NSString*)restorableID
                      kind:(FiberRestorableKind)kind
                      date:(NSDate*)date
               windowCount:(NSInteger)windowCount
                     pages:(NSArray<FiberRestorablePage*>*)pages
    NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@property(readonly, copy) NSString* restorableID;
@property(readonly) FiberRestorableKind kind;
// When the window closed, or the session ended.
@property(readonly, copy) NSDate* date;
@property(readonly) NSInteger windowCount;
// Its tabs, window by window, in order.
@property(readonly, copy) NSArray<FiberRestorablePage*>* pages;

@end

NS_ASSUME_NONNULL_END
