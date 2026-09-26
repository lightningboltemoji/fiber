#import "fiber/browser/fiber_location_field.h"

namespace {

constexpr CGFloat kHorizontalTextInset = 12;

}  // namespace

// Draws the field as a pill: text inset from the rounded ends and centered
// vertically, and a focus ring that follows the pill's outline. The pill's
// background comes from the view the field is placed in.
@interface FiberLocationFieldCell : NSTextFieldCell
@end

@implementation FiberLocationFieldCell {
  // Set while super positions the field editor; it passes back the rect we
  // already adjusted.
  BOOL _settingUpEditor;
}

- (NSRect)drawingRectForBounds:(NSRect)bounds {
  NSRect rect = [super drawingRectForBounds:bounds];
  if (_settingUpEditor) {
    return rect;
  }
  rect = NSInsetRect(rect, kHorizontalTextInset, 0);
  const CGFloat textHeight = [self cellSizeForBounds:rect].height;
  if (textHeight < NSHeight(rect)) {
    rect.origin.y += floor((NSHeight(rect) - textHeight) / 2);
    rect.size.height = textHeight;
  }
  return rect;
}

- (void)editWithFrame:(NSRect)frame
               inView:(NSView*)controlView
               editor:(NSText*)editor
             delegate:(id)delegate
                event:(NSEvent*)event {
  const NSRect rect = [self drawingRectForBounds:frame];
  _settingUpEditor = YES;
  [super editWithFrame:rect
                inView:controlView
                editor:editor
              delegate:delegate
                 event:event];
  _settingUpEditor = NO;
}

- (void)selectWithFrame:(NSRect)frame
                 inView:(NSView*)controlView
                 editor:(NSText*)editor
               delegate:(id)delegate
                  start:(NSInteger)start
                 length:(NSInteger)length {
  const NSRect rect = [self drawingRectForBounds:frame];
  _settingUpEditor = YES;
  [super selectWithFrame:rect
                  inView:controlView
                  editor:editor
                delegate:delegate
                   start:start
                  length:length];
  _settingUpEditor = NO;
}

- (void)drawFocusRingMaskWithFrame:(NSRect)cellFrame
                            inView:(NSView*)controlView {
  const CGFloat radius = NSHeight(cellFrame) / 2;
  [[NSBezierPath bezierPathWithRoundedRect:cellFrame
                                   xRadius:radius
                                   yRadius:radius] fill];
}

- (NSRect)focusRingMaskBoundsForFrame:(NSRect)cellFrame
                               inView:(NSView*)controlView {
  return cellFrame;
}

@end

@implementation FiberLocationField {
  NSString* __strong _url;
  NSString* __strong _displayString;
}

+ (Class)cellClass {
  return [FiberLocationFieldCell class];
}

- (instancetype)initWithFrame:(NSRect)frame {
  if ((self = [super initWithFrame:frame])) {
    _url = @"";
    _displayString = @"";
    self.placeholderString = @"Search or enter address";
    self.bezeled = NO;
    self.bordered = NO;
    self.drawsBackground = NO;
    self.editable = YES;
    self.selectable = YES;
    self.usesSingleLineMode = YES;
    self.alignment = NSTextAlignmentCenter;
    self.cell.scrollable = YES;
    self.cell.sendsActionOnEndEditing = NO;
  }
  return self;
}

- (BOOL)isEditing {
  return self.currentEditor != nil;
}

- (BOOL)hasEdits {
  return self.editing && ![self.currentEditor.string isEqualToString:_url];
}

- (void)setURL:(NSString*)url displayString:(NSString*)displayString {
  _url = [url copy];
  _displayString = [displayString copy];
  if (!self.editing) {
    self.stringValue = _displayString;
  }
}

- (void)revertEdits {
  NSText* editor = self.currentEditor;
  editor.string = _url;
  [editor selectAll:nil];
}

- (BOOL)becomeFirstResponder {
  // Swap in the full URL before editing starts; super then selects it all.
  if (!self.editing) {
    self.alignment = NSTextAlignmentNatural;
    self.stringValue = _url;
  }
  return [super becomeFirstResponder];
}

- (void)mouseDown:(NSEvent*)event {
  // Like other browsers, the click that starts editing selects the whole URL
  // rather than placing the caret; later clicks behave normally.
  const BOOL wasEditing = self.editing;
  [super mouseDown:event];
  if (!wasEditing) {
    [self.currentEditor selectAll:nil];
  }
}

- (void)textDidEndEditing:(NSNotification*)notification {
  // Sends the action on Return, which may move focus to the page.
  [super textDidEndEditing:notification];
  if (!self.editing) {
    self.alignment = NSTextAlignmentCenter;
    self.stringValue = _displayString;
  }
}

@end
