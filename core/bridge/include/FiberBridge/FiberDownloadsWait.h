#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

// What's waiting for downloads to finish.
typedef NS_ENUM(NSInteger, FiberDownloadsWaitReason) {
  FiberDownloadsWaitReasonQuit,
  // Closing a window whose downloads would be cancelled with it (the last
  // Incognito window's, say).
  FiberDownloadsWaitReasonCloseWindow,
};

// A download that's in progress or paused.
NS_SWIFT_SENDABLE
@interface FiberDownloadState : NSObject

- (instancetype)initWithDownloadID:(NSString*)downloadID
                          fileName:(NSString*)fileName
                        statusText:(NSString*)statusText
                          progress:(double)progress
                            paused:(BOOL)paused NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

// Stable for the download's life.
@property(readonly, copy) NSString* downloadID;
@property(readonly, copy) NSString* fileName;
// Its size and time left, "12.3/45.6 MB, 2 mins left", or that it's paused.
@property(readonly, copy) NSString* statusText;
// From 0 to 1, or negative while its size isn't known.
@property(readonly) double progress;
@property(readonly) BOOL paused;

@end

NS_SWIFT_UI_ACTOR
@protocol FiberDownloadsWaitActions <NSObject>

- (void)cancelDownloadWithID:(NSString*)downloadID;
- (void)resumeDownloadWithID:(NSString*)downloadID;
// Quit or close now, cancelling the downloads left.
- (void)proceedNow;
// Don't quit or close after all.
- (void)stopWaiting;

@end

// The downloads a quit or a window's close is waiting for, listed over the
// veiled page in a window. When they're done, what was waiting goes ahead.
NS_SWIFT_UI_ACTOR
@protocol FiberDownloadsWait <NSObject>

// Replaces the list, in order.
- (void)setDownloads:(NSArray<FiberDownloadState*>*)downloads;
// Takes the list down. The actions get nothing more.
- (void)close;

@end

NS_SWIFT_UI_ACTOR
@interface FiberDownloadsWaitFactory : NSObject

// Shows the wait in `window`, which comes forward.
+ (id<FiberDownloadsWait>)waitWithReason:(FiberDownloadsWaitReason)reason
                                  window:(NSWindow*)window
                                 actions:(id<FiberDownloadsWaitActions>)actions;

- (instancetype)init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
