#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

// What a suggestion is, for its icon.
typedef NS_ENUM(NSInteger, FiberSuggestionKind) {
  // A page: from history, a typed URL, or the search engine's suggestions.
  FiberSuggestionKindPage,
  FiberSuggestionKindBookmark,
  FiberSuggestionKindSearch,
  FiberSuggestionKindSearchHistory,
  FiberSuggestionKindTrendingSearch,
  FiberSuggestionKindCalculator,
  // From an extension (its omnibox keyword).
  FiberSuggestionKindExtension,
  // A browser action, like "Clear browsing data".
  FiberSuggestionKindAction,
  // Information rather than something to open, like a tip. Not selectable.
  FiberSuggestionKindMessage,
};

// How to draw a stretch of a suggestion's text.
typedef NS_OPTIONS(NSUInteger, FiberTextStyle) {
  FiberTextStyleNone = 0,
  FiberTextStyleURL = 1 << 0,
  // Matches what the user typed.
  FiberTextStyleMatch = 1 << 1,
  // Secondary, helper text.
  FiberTextStyleDim = 1 << 2,
};

// The part of a suggestion that's selected, which is what Return does.
typedef NS_ENUM(NSInteger, FiberSuggestionPart) {
  // Opens the suggestion.
  FiberSuggestionPartRow,
  // Searches with the suggestion's keyword: types the rest of the query into
  // its search engine or extension (keyword mode).
  FiberSuggestionPartKeyword,
  // Runs one of its actions, like Switch to Tab.
  FiberSuggestionPartAction,
  // Removes it from history.
  FiberSuggestionPartRemove,
};

// Keys that move the selection through the suggestions.
typedef NS_ENUM(NSInteger, FiberSuggestionMove) {
  FiberSuggestionMoveUp,
  FiberSuggestionMoveDown,
  FiberSuggestionMovePageUp,
  FiberSuggestionMovePageDown,
  // Tab and Shift-Tab: also step through each suggestion's parts.
  FiberSuggestionMoveNext,
  FiberSuggestionMovePrevious,
};

NS_SWIFT_SENDABLE
@interface FiberTextRun : NSObject

- (instancetype)initWithRange:(NSRange)range
                        style:(FiberTextStyle)style NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

// In UTF-16 code units, like NSString.
@property(readonly) NSRange range;
@property(readonly) FiberTextStyle style;

@end

// One row of the command palette's suggestions, as Chrome's omnibox would
// show it.
NS_SWIFT_SENDABLE
@interface FiberSuggestion : NSObject

- (instancetype)initWithKind:(FiberSuggestionKind)kind
                    contents:(NSString*)contents
                contentsRuns:(NSArray<FiberTextRun*>*)contentsRuns
                      detail:(NSString*)detail
                  detailRuns:(NSArray<FiberTextRun*>*)detailRuns
                     favicon:(nullable NSImage*)favicon
                      header:(NSString*)header
                keywordLabel:(NSString*)keywordLabel
                actionTitles:(NSArray<NSString*>*)actionTitles
                   removable:(BOOL)removable
                      hidden:(BOOL)hidden NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@property(readonly) FiberSuggestionKind kind;
// The main text: a page's title or URL, or a search's query.
@property(readonly, copy) NSString* contents;
// Covers all of `contents`, in order.
@property(readonly, copy) NSArray<FiberTextRun*>* contentsRuns;
// Secondary text, like a page's URL beside its title. May be empty.
@property(readonly, copy) NSString* detail;
@property(readonly, copy) NSArray<FiberTextRun*>* detailRuns;
@property(readonly, nullable) NSImage* favicon;
// A heading to show above this suggestion, which starts a group (like
// "Recent searches"). Usually empty.
@property(readonly, copy) NSString* header;
// What searching with the suggestion's keyword does, like "Search YouTube".
// Empty if it has none.
@property(readonly, copy) NSString* keywordLabel;
// Buttons for the suggestion's actions, like "Switch to this tab".
@property(readonly, copy) NSArray<NSString*>* actionTitles;
// Whether the user can remove it (it's from their history).
@property(readonly) BOOL isRemovable;
// Hidden suggestions keep their place, so indexes still line up, but aren't
// shown.
@property(readonly) BOOL isHidden;

@end

// What the user does in the command palette's field and suggestions. It's
// Chrome's omnibox underneath: the browser suggests, autocompletes, and opens
// what the user picks.
NS_SWIFT_UI_ACTOR
@protocol FiberOmniboxActions <NSObject>

// The palette opened, or closed. Closing discards what the user typed.
- (void)omniboxDidFocus;
- (void)omniboxDidBlur;
// The user changed the field's text or selection: typed, deleted, pasted, or
// moved the caret. `text` includes any inline autocompletion still selected.
// `composing` is whether an input method is composing text in the field.
- (void)omniboxTextDidChange:(NSString*)text
               selectedRange:(NSRange)selectedRange
                   composing:(BOOL)composing;
- (void)omniboxMoveSelection:(FiberSuggestionMove)move;
// Return: opens the selected suggestion, or what's typed. The event's modifier
// keys decide where it opens.
- (void)omniboxOpenSelectionWithEvent:(nullable NSEvent*)event;
// A click on a suggestion, or one of its parts. `actionIndex` is for
// FiberSuggestionPartAction.
- (void)omniboxOpenSuggestionAtIndex:(NSInteger)index
                                part:(FiberSuggestionPart)part
                         actionIndex:(NSInteger)actionIndex
                               event:(nullable NSEvent*)event;
- (void)omniboxRemoveSuggestionAtIndex:(NSInteger)index;
// Backspace at the start of the field in keyword mode: back to a plain search.
- (void)omniboxClearKeyword;

@end

// The command palette, as the omnibox's view: the browser tells it what its
// field and suggestions show.
NS_SWIFT_UI_ACTOR
@protocol FiberOmnibox <NSObject>

// Set once, before the palette opens.
@property(nonatomic, nullable) id<FiberOmniboxActions> actions;

// Opens the palette (Command-L, and new tabs). If it's already open, it stays
// as it is.
- (void)focus;
// What the field shows, with `selectedRange` selected; an empty range is the
// caret. Inline autocompletion is the selected end of `text`.
- (void)setText:(NSString*)text selectedRange:(NSRange)selectedRange;
// In keyword mode, where the query goes, like "Search YouTube". Empty
// otherwise.
- (void)setKeywordLabel:(NSString*)label;
// Replaces the suggestions. Empty closes the list.
- (void)setSuggestions:(NSArray<FiberSuggestion*>*)suggestions;
// Which suggestion, and which of its parts, Return opens. `index` is -1 when
// it's what's typed rather than a suggestion.
- (void)setSelectedSuggestionIndex:(NSInteger)index
                              part:(FiberSuggestionPart)part
                       actionIndex:(NSInteger)actionIndex;

@end

NS_ASSUME_NONNULL_END
