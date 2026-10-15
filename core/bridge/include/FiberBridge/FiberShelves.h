#import <AppKit/AppKit.h>

@class FiberPinState;

NS_ASSUME_NONNULL_BEGIN

// One of the profile's shelves: a named list of pages the user keeps to come
// back to, which every window lists in its tab overlay beside its own tabs.
// Its pages are kept as pins are, and are FiberPinStates: closing one's tab
// keeps the page, until the user removes it.
NS_SWIFT_SENDABLE
@interface FiberShelfState : NSObject

- (instancetype)initWithID:(NSString*)shelfID
                      name:(NSString*)name
                     pages:(NSArray<FiberPinState*>*)pages
    NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@property(readonly, copy) NSString* shelfID;
@property(readonly, copy) NSString* name;
// In the order the user arranged them. A page's ID is unique among the pins'
// and every shelf's.
@property(readonly, copy) NSArray<FiberPinState*>* pages;

@end

// What the user does with the profile's shelves, from any of its windows.
NS_SWIFT_UI_ACTOR
@protocol FiberShelvesActions <NSObject>

// Adds an empty shelf after the others, and returns its ID.
- (NSString*)addShelfNamed:(NSString*)name;
- (void)renameShelfWithID:(NSString*)shelfID to:(NSString*)name;
// Removes the shelf and its pages. Their open tabs stay, as ordinary tabs.
- (void)removeShelfWithID:(NSString*)shelfID;
// Selects the page's tab in this window, or opens it in a new one.
- (void)openShelfPageWithID:(NSString*)pageID;
// Keeps the tab's page on the shelf, last, the tab becoming its page's.
- (void)moveTabWithID:(NSInteger)tabID toShelfWithID:(NSString*)shelfID;
// Moves a kept page to the end of another shelf. To none (an empty
// `shelfID`), it's no longer kept, its tab staying, or opening behind the
// active one if it wasn't open here.
- (void)moveShelfPageWithID:(NSString*)pageID
              toShelfWithID:(NSString*)shelfID;
// No longer keeps the page. Its tab, if it's open, stays as an ordinary tab.
- (void)removeShelfPageWithID:(NSString*)pageID;

@end

// The profile's shelves, which the tab overlay lists after the window's own
// tabs ("Home").
NS_SWIFT_UI_ACTOR
@protocol FiberShelves <NSObject>

// Set once, before the first shelves.
@property(nonatomic, nullable) id<FiberShelvesActions> actions;

// Replaces the shelves, in order. Their pages' open tabs are among the
// window's tabs too. Never called for a window without them, like an
// Incognito one.
- (void)setShelves:(NSArray<FiberShelfState*>*)shelves;

@end

NS_ASSUME_NONNULL_END
