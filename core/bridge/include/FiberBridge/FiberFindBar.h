#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

// What the user does in the find bar. It's Chrome's find in page underneath:
// the browser finds in the active tab's page, and keeps a session per tab.
NS_SWIFT_UI_ACTOR
@protocol FiberFindBarActions <NSObject>

// The user changed the field's text (typing, deleting, pasting), once an
// input method is done composing it.
- (void)findBarTextDidChange:(NSString*)text;
// Return and Shift-Return, and the bar's arrows.
- (void)findBarFindNext;
- (void)findBarFindPrevious;
// Escape in the field, or the close button.
- (void)findBarClose;
// The field took the keyboard, or gave it up.
- (void)findBarFocusDidChange:(BOOL)focused;

@end

// The window's find bar (Command-F), in its top-right corner. The browser
// shows and hides it, fills in its field, and counts the matches.
NS_SWIFT_UI_ACTOR
@protocol FiberFindBar <NSObject>

// Set once, before the bar shows.
@property(nonatomic, nullable) id<FiberFindBarActions> actions;
@property(readonly, copy) NSString* text;
@property(readonly) NSRange selectedRange;
// Whether the field has the keyboard.
@property(readonly) BOOL hasFocus;

// If `focus`, the field takes the keyboard, and the omnibar or command
// palette closes. Already showing, it stays.
- (void)showAnimated:(BOOL)animated focus:(BOOL)focus;
// The browser moves the keyboard off the field first.
- (void)hideAnimated:(BOOL)animated;
// Focuses the field with its text selected.
- (void)focusAndSelectAll;
// What an input method is composing stays until it's done.
- (void)setText:(NSString*)text selectedRange:(NSRange)selectedRange;
// `count` is -1 while there's nothing to count, or until counted.
// `activeMatch` is the current match, from 1, or 0 if there's none yet.
- (void)setMatchCount:(NSInteger)count activeMatch:(NSInteger)activeMatch;

@end

NS_ASSUME_NONNULL_END
