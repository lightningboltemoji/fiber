#ifndef FIBER_BROWSER_FIBER_LOCATION_FIELD_H_
#define FIBER_BROWSER_FIBER_LOCATION_FIELD_H_

#import <Cocoa/Cocoa.h>

// The address field, drawn as a borderless pill to sit on a capsule background.
// While idle it shows a short, centered form of the page's URL (usually just
// the host). Focusing it swaps in the full URL, and the first click selects all
// of it.
@interface FiberLocationField : NSTextField

@property(readonly, nonatomic, getter=isEditing) BOOL editing;
// Whether the text being edited differs from the current URL.
@property(readonly, nonatomic) BOOL hasEdits;

// Sets the page's full URL and its short display form. The visible text only
// changes once the user isn't editing.
- (void)setURL:(NSString*)url displayString:(NSString*)displayString;
// While editing, discards the user's changes and selects the full URL.
- (void)revertEdits;

@end

#endif  // FIBER_BROWSER_FIBER_LOCATION_FIELD_H_
