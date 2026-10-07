#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

// How a prompt's button is pressed, and how it looks.
typedef NS_ENUM(NSInteger, FiberPromptButtonRole) {
  // Tinted; Return presses it.
  FiberPromptButtonRoleDefault,
  // Tinted, but only a click presses it, and not until the prompt has been up
  // a moment: for what a page could trick the user into accepting (adding an
  // extension, say), as Chrome guards its own dialogs' buttons.
  FiberPromptButtonRoleConfirm,
  // Escape presses it. Without one, Escape dismisses the prompt.
  FiberPromptButtonRoleCancel,
  FiberPromptButtonRoleOther,
};

NS_SWIFT_SENDABLE
@interface FiberPromptButton : NSObject

- (instancetype)initWithButtonID:(NSInteger)buttonID
                           title:(NSString*)title
                            role:(FiberPromptButtonRole)role
    NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

// Identifies the button to the prompt's actions.
@property(readonly) NSInteger buttonID;
@property(readonly, copy) NSString* title;
@property(readonly) FiberPromptButtonRole role;

@end

// A line in a prompt's list (one of the things an extension asks to do, say),
// with any detail under it.
NS_SWIFT_SENDABLE
@interface FiberPromptListItem : NSObject

- (instancetype)initWithText:(NSString*)text
                      detail:(NSString*)detail NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@property(readonly, copy) NSString* text;
// Empty for none. May run to several lines.
@property(readonly, copy) NSString* detail;

@end

// What a prompt's text field holds, which says what AutoFill may offer.
typedef NS_ENUM(NSInteger, FiberPromptFieldKind) {
  FiberPromptFieldKindText,
  FiberPromptFieldKindUsername,
  // Hides what's typed.
  FiberPromptFieldKindPassword,
};

// A text field in a prompt (a username, say), named by its placeholder.
NS_SWIFT_SENDABLE
@interface FiberPromptField : NSObject

- (instancetype)initWithPlaceholder:(NSString*)placeholder
                               text:(NSString*)text
                               kind:(FiberPromptFieldKind)kind
    NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@property(readonly, copy) NSString* placeholder;
// What it holds at first.
@property(readonly, copy) NSString* text;
@property(readonly) FiberPromptFieldKind kind;

@end

// What a prompt is about, which its icon shows unless it has an image of its
// own.
typedef NS_ENUM(NSInteger, FiberPromptTopic) {
  FiberPromptTopicGeneral,
  FiberPromptTopicLocation,
  FiberPromptTopicCamera,
  FiberPromptTopicMicrophone,
  FiberPromptTopicNotifications,
  FiberPromptTopicClipboard,
  FiberPromptTopicFiles,
  FiberPromptTopicDownloads,
  // Opening another app, or links of a kind, with a site.
  FiberPromptTopicOpenApp,
  FiberPromptTopicSignIn,
  // Leaving a page that may lose what was typed into it.
  FiberPromptTopicLeave,
  FiberPromptTopicExtension,
  // Devices on the user's local network.
  FiberPromptTopicLocalNetwork,
  FiberPromptTopicMIDI,
  // Placing windows across the user's displays.
  FiberPromptTopicWindows,
  // A site embedded in another using what it saved about the user.
  FiberPromptTopicStorageAccess,
  FiberPromptTopicKeyboardLock,
  FiberPromptTopicPointerLock,
  // Virtual and augmented reality, and hand tracking.
  FiberPromptTopicSpatial,
};

// What a prompt says: from the top, a title with a line over it and a
// message under it, a list, a checkbox, text fields, and the buttons, beside
// an icon.
NS_SWIFT_SENDABLE
@interface FiberPromptContent : NSObject

// Without fields or a checkbox.
- (instancetype)initWithIcon:(nullable NSImage*)icon
                       topic:(FiberPromptTopic)topic
                     eyebrow:(NSString*)eyebrow
                       title:(NSString*)title
                     message:(NSString*)message
                 listHeading:(NSString*)listHeading
                   listItems:(NSArray<FiberPromptListItem*>*)listItems
                     buttons:(NSArray<FiberPromptButton*>*)buttons;
- (instancetype)initWithIcon:(nullable NSImage*)icon
                       topic:(FiberPromptTopic)topic
                     eyebrow:(NSString*)eyebrow
                       title:(NSString*)title
                     message:(NSString*)message
                 listHeading:(NSString*)listHeading
                   listItems:(NSArray<FiberPromptListItem*>*)listItems
                      fields:(NSArray<FiberPromptField*>*)fields
               checkboxTitle:(NSString*)checkboxTitle
                     buttons:(NSArray<FiberPromptButton*>*)buttons
    NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

// What the prompt is about, like an extension's icon. Without one, `topic`'s.
@property(readonly, nullable) NSImage* icon;
@property(readonly) FiberPromptTopic topic;
// Over the title, smaller: who's asking, say. Empty for none.
@property(readonly, copy) NSString* eyebrow;
@property(readonly, copy) NSString* title;
// Empty for none. May run to several lines, and paragraphs.
@property(readonly, copy) NSString* message;
// Over the list, like "It can:". Empty for none.
@property(readonly, copy) NSString* listHeading;
@property(readonly, copy) NSArray<FiberPromptListItem*>* listItems;
// The first takes the keyboard focus, and Return in any presses the default
// button.
@property(readonly, copy) NSArray<FiberPromptField*>* fields;
// Empty for none. It starts unchecked.
@property(readonly, copy) NSString* checkboxTitle;
// In order, left to right.
@property(readonly, copy) NSArray<FiberPromptButton*>* buttons;

@end

// How a prompt ended. Exactly one of these is called, once, after the prompt
// is gone.
NS_SWIFT_UI_ACTOR
@protocol FiberPromptActions <NSObject>

- (void)promptDidPressButtonWithID:(NSInteger)buttonID;
// The prompt ended without an answer: Escape dismissed it, -close was called,
// another prompt took its place, or its tab or window closed.
- (void)promptDidDismiss;

@end

NS_SWIFT_UI_ACTOR
@protocol FiberPrompt <NSObject>

// The fields' text, in order, and whether the checkbox is checked: as they
// stand, or as they were when the prompt ended.
@property(readonly, copy) NSArray<NSString*>* fieldValues;
@property(readonly) BOOL checkboxChecked;

// Ends the prompt. Its actions get -promptDidDismiss.
- (void)close;

@end

// Prompts are glass bubbles over the page, which stays usable around them.
// One takes the keyboard as it shows, unless something else in the window
// (the omnibar, say) has it, and gives it back when the user clicks the page.
NS_SWIFT_UI_ACTOR
@interface FiberPromptFactory : NSObject

// Asks over the page of tab `tabID` in `window`, while that tab is active, in
// place of any other of the tab's. If `window` isn't a browser window, the
// prompt is dismissed at once (after this returns).
+ (id<FiberPrompt>)promptWithContent:(FiberPromptContent*)content
                               tabID:(NSInteger)tabID
                              window:(NSWindow*)window
                             actions:(id<FiberPromptActions>)actions;

// Asks over the page in `window`, whichever tab is active, ahead of its tabs'
// prompts and in place of any other of the window's, bringing it forward. If
// `window` isn't a browser window, it's dismissed at once (after this returns).
+ (id<FiberPrompt>)promptWithContent:(FiberPromptContent*)content
                              window:(NSWindow*)window
                             actions:(id<FiberPromptActions>)actions;

- (instancetype)init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
