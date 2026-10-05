#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// What the window shows in place of a page whose renderer is gone (it crashed,
// or was killed for memory): Chrome's words, and a button, which usually
// reloads it.
NS_SWIFT_SENDABLE
@interface FiberSadTab : NSObject

- (instancetype)initWithTitle:(NSString*)title
                      message:(NSString*)message
                  suggestions:(NSArray<NSString*>*)suggestions
                    errorCode:(NSString*)errorCode
                  buttonTitle:(NSString*)buttonTitle
                    helpTitle:(NSString*)helpTitle NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@property(readonly, copy) NSString* title;
@property(readonly, copy) NSString* message;
// What to try, after the page crashes again. Empty for none.
@property(readonly, copy) NSArray<NSString*>* suggestions;
// Why it's gone, like "Error code: SIGSEGV".
@property(readonly, copy) NSString* errorCode;
@property(readonly, copy) NSString* buttonTitle;
// A link to Chrome's help, like "Learn more".
@property(readonly, copy) NSString* helpTitle;

@end

// What a window shows of its active tab's page: the toolbar's controls and the
// window title.
NS_SWIFT_SENDABLE
@interface FiberPageState : NSObject

- (instancetype)initWithDisplayURL:(NSString*)displayURL
                             title:(NSString*)title
                         canGoBack:(BOOL)canGoBack
                      canGoForward:(BOOL)canGoForward
                           loading:(BOOL)loading
                        newTabPage:(BOOL)newTabPage
                            sadTab:(nullable FiberSadTab*)sadTab
                    keyPassthrough:(BOOL)keyPassthrough
    NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

// A short form of the URL (usually just the host), shown in the toolbar. Empty
// for pages that don't show their URL, like the New Tab page.
@property(readonly, copy) NSString* displayURL;
@property(readonly, copy) NSString* title;
@property(readonly) BOOL canGoBack;
@property(readonly) BOOL canGoForward;
@property(readonly) BOOL isLoading;
// Fiber's New Tab page (chrome://newtab), which the window draws.
@property(readonly) BOOL isNewTabPage;
// The page's renderer is gone; the window draws this in its place.
@property(readonly, nullable) FiberSadTab* sadTab;
// The tab has key passthrough (see FiberCommandKeyPassthrough).
@property(readonly) BOOL hasKeyPassthrough;

@end

NS_ASSUME_NONNULL_END
