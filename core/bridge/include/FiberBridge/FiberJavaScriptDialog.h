#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, FiberJavaScriptDialogKind) {
  // An OK button.
  FiberJavaScriptDialogKindAlert,
  // OK and Cancel buttons.
  FiberJavaScriptDialogKindConfirm,
  // OK and Cancel buttons and a text field.
  FiberJavaScriptDialogKindPrompt,
};

// A page's alert(), confirm(), or prompt(), or its confirmation before leaving
// the page.
NS_SWIFT_SENDABLE
@interface FiberJavaScriptDialogContent : NSObject

- (instancetype)initWithKind:(FiberJavaScriptDialogKind)kind
                       title:(NSString*)title
                     message:(NSString*)message
           defaultPromptText:(NSString*)defaultPromptText
           acceptButtonTitle:(NSString*)acceptButtonTitle
           cancelButtonTitle:(NSString*)cancelButtonTitle
    NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@property(readonly) FiberJavaScriptDialogKind kind;
@property(readonly, copy) NSString* title;
@property(readonly, copy) NSString* message;
// The prompt's initial text. Unused by other kinds.
@property(readonly, copy) NSString* defaultPromptText;
@property(readonly, copy) NSString* acceptButtonTitle;
// Unused by alerts.
@property(readonly, copy) NSString* cancelButtonTitle;

@end

// How a dialog ended. Exactly one of these is called, once, after the dialog
// is gone.
NS_SWIFT_UI_ACTOR
@protocol FiberJavaScriptDialogActions <NSObject>

// The user pressed OK. `input` is the prompt's text, or empty for other kinds.
- (void)dialogDidAcceptWithInput:(NSString*)input;
- (void)dialogDidCancel;
// The dialog ended without an answer: -close was called, or its window went
// away.
- (void)dialogDidDismiss;

@end

NS_SWIFT_UI_ACTOR
@protocol FiberJavaScriptDialog <NSObject>

// The prompt's current text. Empty for other kinds.
@property(readonly, copy) NSString* userInput;

// Ends the dialog. Its actions get -dialogDidDismiss.
- (void)close;

@end

NS_SWIFT_UI_ACTOR
@interface FiberJavaScriptDialogFactory : NSObject

// Shows the dialog as a sheet on `window`.
+ (id<FiberJavaScriptDialog>)
    dialogWithContent:(FiberJavaScriptDialogContent*)content
               window:(NSWindow*)window
              actions:(id<FiberJavaScriptDialogActions>)actions;

// Asks whether to leave the page, which asked with a beforeunload handler (or
// whether to reload it; `content` says which): over the page, veiled, in
// `window`, which comes forward. `site` names the page's site. `content`'s
// kind is confirm.
+ (id<FiberJavaScriptDialog>)
    leavePromptWithContent:(FiberJavaScriptDialogContent*)content
                      site:(NSString*)site
                    window:(NSWindow*)window
                   actions:(id<FiberJavaScriptDialogActions>)actions;

- (instancetype)init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
