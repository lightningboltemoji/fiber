#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

// Avatars are numbered as Chrome numbers its default avatars
// (chrome/browser/profiles/profile_avatar_icon_util.h); Fiber draws its own
// for each.

// A profile, as the profile switcher shows it.
NS_SWIFT_SENDABLE
@interface FiberProfile : NSObject

- (instancetype)initWithProfileID:(NSString*)profileID
                             name:(NSString*)name
                      avatarIndex:(NSInteger)avatarIndex
                          current:(BOOL)current NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

// Identifies it to the switcher's actions: its directory's path.
@property(readonly, copy) NSString* profileID;
@property(readonly, copy) NSString* name;
@property(readonly) NSInteger avatarIndex;
// The profile of the window the switcher is in.
@property(readonly) BOOL current;

@end

// A profile in another browser that a new profile can be imported from.
NS_SWIFT_SENDABLE
@interface FiberImportSource : NSObject

- (instancetype)initWithSourceID:(NSInteger)sourceID
                            name:(NSString*)name
                          detail:(NSString*)detail
                     avatarIndex:(NSInteger)avatarIndex
                         picture:(nullable NSImage*)picture
    NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@property(readonly) NSInteger sourceID;
@property(readonly, copy) NSString* name;
// Under the name, like its account. Empty for none.
@property(readonly, copy) NSString* detail;
@property(readonly) NSInteger avatarIndex;
// Its account's picture, shown in place of its avatar.
@property(readonly, nullable) NSImage* picture;

@end

typedef NS_ENUM(NSInteger, FiberProfileSwitcherPage) {
  // The profiles.
  FiberProfileSwitcherPageProfiles,
  FiberProfileSwitcherPageNewProfile,
};

// What the switcher offers: the profiles, in order, then a new one, and one
// imported from `importBrowser` (like "Chrome") if it has `importSources`.
NS_SWIFT_SENDABLE
@interface FiberProfileSwitcherContent : NSObject

- (instancetype)initWithProfiles:(NSArray<FiberProfile*>*)profiles
           newProfileAvatarIndex:(NSInteger)newProfileAvatarIndex
                   importBrowser:(NSString*)importBrowser
                      importIcon:(nullable NSImage*)importIcon
                   importSources:(NSArray<FiberImportSource*>*)importSources
                            page:(FiberProfileSwitcherPage)page
    NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@property(readonly, copy) NSArray<FiberProfile*>* profiles;
// The avatar a new profile starts with.
@property(readonly) NSInteger newProfileAvatarIndex;
@property(readonly, copy) NSString* importBrowser;
@property(readonly, nullable) NSImage* importIcon;
@property(readonly, copy) NSArray<FiberImportSource*>* importSources;
// Where it opens.
@property(readonly) FiberProfileSwitcherPage page;

@end

NS_SWIFT_UI_ACTOR
@protocol FiberProfileSwitcherActions <NSObject>

// Opens a window for the profile, or brings its last used forward. The
// switcher closes.
- (void)switchToProfileWithID:(NSString*)profileID;
// Creates a profile and opens a window for it. The switcher closes.
- (void)createProfileWithName:(NSString*)name avatarIndex:(NSInteger)avatarIndex;
// Creates a profile from the source's data, and opens a window for it. The
// switcher shows the progress (-setImportProgress:, -setImportFailure:) until
// it's closed.
- (void)importSourceWithID:(NSInteger)sourceID;
// The switcher is gone: the user left it, -close was called, a prompt took
// its place, or its window closed.
- (void)profileSwitcherDidClose;

@end

NS_SWIFT_UI_ACTOR
@protocol FiberProfileSwitcher <NSObject>

// The profiles changed while it's up.
- (void)setProfiles:(NSArray<FiberProfile*>*)profiles;
// What the import is doing, like "Copying passwords…".
- (void)setImportProgress:(NSString*)step;
// The import stopped; the user can try again or another source.
- (void)setImportFailure:(NSString*)message;
- (void)close;

@end

NS_SWIFT_UI_ACTOR
@interface FiberProfileSwitcherFactory : NSObject

// Shows the switcher over the page, veiled, in `window`, which comes forward.
// If `window` isn't a browser window or is waiting on the user, it closes at
// once (after this returns).
+ (id<FiberProfileSwitcher>)switcherWithContent:
                                (FiberProfileSwitcherContent*)content
                                          window:(NSWindow*)window
                                         actions:
                                             (id<FiberProfileSwitcherActions>)
                                                 actions;

- (instancetype)init NS_UNAVAILABLE;

@end

// Fiber's avatars for Chrome's own surfaces (chrome://theme, the Profiles
// menu).
NS_SWIFT_UI_ACTOR
@interface FiberProfileAvatars : NSObject

// Avatar `avatarIndex` as a PNG `pixelSize` pixels square.
+ (NSData*)pngForAvatarIndex:(NSInteger)avatarIndex
                   pixelSize:(NSInteger)pixelSize;

- (instancetype)init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
