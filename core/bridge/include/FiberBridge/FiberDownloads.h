#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, FiberDownloadStatus) {
  // Downloading, or paused.
  FiberDownloadStatusInProgress,
  // Held until the user keeps or discards it: a kind of file or a site that
  // may be harmful, or a file from an insecure connection.
  FiberDownloadStatusNeedsReview,
  FiberDownloadStatusComplete,
  // Stopped short by an error; it may be able to pick up where it left off.
  FiberDownloadStatusFailed,
  FiberDownloadStatusCancelled,
};

// A download, as it is now.
NS_SWIFT_SENDABLE
@interface FiberDownloadState : NSObject

- (instancetype)initWithDownloadID:(NSString*)downloadID
                          fileName:(NSString*)fileName
                          filePath:(NSString*)filePath
                            status:(FiberDownloadStatus)status
                        statusText:(NSString*)statusText
                       warningText:(NSString*)warningText
                            origin:(NSString*)origin
                     receivedBytes:(int64_t)receivedBytes
                        totalBytes:(int64_t)totalBytes
                          progress:(double)progress
                     timeRemaining:(NSTimeInterval)timeRemaining
                            paused:(BOOL)paused
                         canResume:(BOOL)canResume
                          canRetry:(BOOL)canRetry
                           canKeep:(BOOL)canKeep
                       fileMissing:(BOOL)fileMissing
    NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

// Stable for the download's life.
@property(readonly, copy) NSString* downloadID;
@property(readonly, copy) NSString* fileName;
// Where the file goes, under the name the user saved it as; empty until
// they've picked it.
@property(readonly, copy) NSString* filePath;
@property(readonly) FiberDownloadStatus status;
// Chrome's one line on it: "12.3/45.6 MB, 2 mins left", "Failed - Network
// error", "Paused".
@property(readonly, copy) NSString* statusText;
// Why it needs review, a sentence or two; empty otherwise.
@property(readonly, copy) NSString* warningText;
// The site it's from, as the user knows it ("example.com"), or empty.
@property(readonly, copy) NSString* origin;
@property(readonly) int64_t receivedBytes;
// 0 while its size isn't known.
@property(readonly) int64_t totalBytes;
// From 0 to 1, or negative while its size isn't known.
@property(readonly) double progress;
// Negative while there's no estimate.
@property(readonly) NSTimeInterval timeRemaining;
@property(readonly) BOOL paused;
@property(readonly) BOOL canResume;
// Failed or cancelled, it can be downloaded again from the start; not if it
// was blocked, or would fail the same way.
@property(readonly) BOOL canRetry;
// Needing review, the user may keep it anyway: not if it's known to be
// malicious, as Chrome only offers to delete those.
@property(readonly) BOOL canKeep;
// It finished, but the file has since been moved or deleted.
@property(readonly) BOOL fileMissing;

@end

// What the user does with the window's downloads. Each takes a download's ID,
// and does nothing if it's gone.
NS_SWIFT_UI_ACTOR
@protocol FiberDownloadsActions <NSObject>

// Opens the finished file, as Chrome would: in its app, or in a tab.
- (void)openDownloadWithID:(NSString*)downloadID;
- (void)showDownloadInFinderWithID:(NSString*)downloadID;
- (void)pauseDownloadWithID:(NSString*)downloadID;
// A paused download, or a failed one that can pick up where it left off.
- (void)resumeDownloadWithID:(NSString*)downloadID;
- (void)cancelDownloadWithID:(NSString*)downloadID;
// Downloads a failed or cancelled download's file again, from the start.
- (void)retryDownloadWithID:(NSString*)downloadID;
// A download that needs review: keeps it (if it can be kept), or deletes it.
- (void)keepDownloadWithID:(NSString*)downloadID;
- (void)discardDownloadWithID:(NSString*)downloadID;
// Takes a finished, cancelled or failed download off the list, and out of
// the profile's download history. A finished file stays where it is.
- (void)removeDownloadWithID:(NSString*)downloadID;
// Removes every finished, cancelled and failed download listed, as
// removeDownloadWithID: does.
- (void)clearDownloads;
// The Downloads page, in a tab.
- (void)showAllDownloads;
// The user can see the downloads now: the tab overlay opened over them. A
// warning that's only shown for a while starts its clock.
- (void)downloadsDidShow;

@end

// The window's downloads, which the tab overlay lists: its profile's recent
// ones.
NS_SWIFT_UI_ACTOR
@protocol FiberDownloads <NSObject>

// Set once, before the first downloads.
@property(nonatomic, nullable) id<FiberDownloadsActions> actions;

// Replaces the list: what's in progress or needs review first, then the rest,
// newest first in each. Empty while an extension has turned the browser's
// download UI off.
- (void)setDownloads:(NSArray<FiberDownloadState*>*)downloads;

@end

NS_ASSUME_NONNULL_END
