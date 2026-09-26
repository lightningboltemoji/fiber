#import "fiber/browser/fiber_window_controller.h"

#include "base/memory/raw_ptr.h"
#include "base/strings/sys_string_conversions.h"
#include "chrome/app/chrome_command_ids.h"
#import "fiber/browser/fiber_location_field.h"
#include "fiber/browser/fiber_window.h"

namespace {

constexpr NSSize kDefaultWindowSize = {1280, 820};
constexpr NSSize kMinWindowSize = {480, 320};
constexpr CGFloat kLocationBarHeight = 36;
constexpr CGFloat kProgressBarHeight = 3;
// Inset from the window's bottom-left corner, clear of its rounding.
constexpr CGFloat kStatusBubbleInset = 10;

NSToolbarItemIdentifier const kBackItemIdentifier = @"fiber.back";
NSToolbarItemIdentifier const kForwardItemIdentifier = @"fiber.forward";
NSToolbarItemIdentifier const kReloadItemIdentifier = @"fiber.reload";
NSToolbarItemIdentifier const kLocationItemIdentifier = @"fiber.location";

}  // namespace

// A thin accent-colored bar along the top of the page that tracks load
// progress, then fills and fades out when loading finishes.
@interface FiberProgressBar : NSView
- (void)setProgress:(double)progress;
- (void)finish;
@end

@implementation FiberProgressBar {
  NSBox* __strong _fill;
  double _progress;
  BOOL _active;
}

- (instancetype)initWithFrame:(NSRect)frame {
  if ((self = [super initWithFrame:frame])) {
    _fill = [[NSBox alloc] initWithFrame:NSZeroRect];
    _fill.boxType = NSBoxCustom;
    _fill.borderWidth = 0;
    _fill.fillColor = NSColor.controlAccentColor;
    [self addSubview:_fill];
    self.wantsLayer = YES;
    self.alphaValue = 0;
  }
  return self;
}

- (NSView*)hitTest:(NSPoint)point {
  return nil;
}

- (NSRect)fillFrameForProgress:(double)progress {
  return NSMakeRect(0, 0, NSWidth(self.bounds) * progress,
                    NSHeight(self.bounds));
}

- (void)resizeSubviewsWithOldSize:(NSSize)oldSize {
  _fill.frame = [self fillFrameForProgress:_progress];
}

- (void)setProgress:(double)progress {
  if (!_active) {
    // Start empty rather than shrinking from the last load's full bar.
    _active = YES;
    _fill.frame = [self fillFrameForProgress:0];
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext* context) {
      context.duration = 0;
      self.animator.alphaValue = 1;
    }];
  }
  _progress = progress;
  [NSAnimationContext runAnimationGroup:^(NSAnimationContext* context) {
    context.duration = 0.2;
    self->_fill.animator.frame = [self fillFrameForProgress:progress];
  }];
}

- (void)finish {
  if (!_active) {
    return;
  }
  _active = NO;
  _progress = 1;
  [NSAnimationContext
      runAnimationGroup:^(NSAnimationContext* context) {
        context.duration = 0.15;
        self->_fill.animator.frame = [self fillFrameForProgress:1];
      }
      completionHandler:^{
        if (self->_active) {
          return;  // Another load started meanwhile.
        }
        [NSAnimationContext runAnimationGroup:^(NSAnimationContext* context) {
          context.duration = 0.3;
          self.animator.alphaValue = 0;
        }];
      }];
}

@end

// Shows a hovered link's URL in the window's bottom-left corner.
@interface FiberStatusBubble : NSBox
- (void)setText:(NSString*)text;
@end

@implementation FiberStatusBubble {
  NSTextField* __strong _label;
}

- (instancetype)initWithFrame:(NSRect)frame {
  if ((self = [super initWithFrame:frame])) {
    self.boxType = NSBoxCustom;
    self.cornerRadius = 7;
    self.borderWidth = 1;
    self.borderColor = NSColor.separatorColor;
    self.fillColor = NSColor.windowBackgroundColor;
    self.contentViewMargins = NSMakeSize(8, 3);

    NSShadow* shadow = [[NSShadow alloc] init];
    shadow.shadowColor = [NSColor colorWithWhite:0 alpha:0.15];
    shadow.shadowOffset = NSMakeSize(0, -1);
    shadow.shadowBlurRadius = 3;
    self.wantsLayer = YES;
    self.shadow = shadow;

    _label = [NSTextField labelWithString:@""];
    _label.font = [NSFont systemFontOfSize:NSFont.smallSystemFontSize];
    _label.textColor = NSColor.secondaryLabelColor;
    _label.lineBreakMode = NSLineBreakByTruncatingMiddle;
    _label.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [self.contentView addSubview:_label];

    self.alphaValue = 0;
  }
  return self;
}

- (NSView*)hitTest:(NSPoint)point {
  return nil;
}

- (void)setText:(NSString*)text {
  if (!text.length) {
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext* context) {
      context.duration = 0.2;
      self.animator.alphaValue = 0;
    }];
    return;
  }

  _label.stringValue = text;
  const NSSize margins = self.contentViewMargins;
  const NSSize labelSize = _label.intrinsicContentSize;
  const CGFloat maxWidth = NSWidth(self.superview.bounds) / 2;
  const NSSize size =
      NSMakeSize(MIN(ceil(labelSize.width) + 2 * margins.width, maxWidth),
                 ceil(labelSize.height) + 2 * margins.height);
  [self setFrameSize:size];
  _label.frame = self.contentView.bounds;

  [NSAnimationContext runAnimationGroup:^(NSAnimationContext* context) {
    context.duration = 0.1;
    self.animator.alphaValue = 1;
  }];
}

@end

@implementation FiberWindowController {
  raw_ptr<fiber::FiberWindow> _owner;
  NSWindow* __strong _window;
  NSToolbarItem* __strong _backItem;
  NSToolbarItem* __strong _forwardItem;
  NSToolbarItem* __strong _reloadItem;
  NSToolbarItem* __strong _locationItem;
  FiberLocationField* __strong _locationField;
  FiberProgressBar* __strong _progressBar;
  FiberStatusBubble* __strong _statusBubble;
}

@synthesize window = _window;

- (instancetype)initWithOwner:(fiber::FiberWindow*)owner {
  if ((self = [super init])) {
    _owner = owner;

    _window = [[NSWindow alloc]
        initWithContentRect:NSMakeRect(0, 0, kDefaultWindowSize.width,
                                       kDefaultWindowSize.height)
                  styleMask:NSWindowStyleMaskTitled |
                            NSWindowStyleMaskClosable |
                            NSWindowStyleMaskMiniaturizable |
                            NSWindowStyleMaskResizable
                    backing:NSBackingStoreBuffered
                      defer:NO];
    _window.releasedWhenClosed = NO;
    _window.delegate = self;
    _window.minSize = kMinWindowSize;
    _window.title = @"Fiber";
    // The page title is kept for the Window menu and Mission Control, but the
    // toolbar takes the title bar's place.
    _window.titleVisibility = NSWindowTitleHidden;
    _window.collectionBehavior |= NSWindowCollectionBehaviorFullScreenPrimary;
    // Fiber will have its own tabs; keep AppKit from merging windows.
    _window.tabbingMode = NSWindowTabbingModeDisallowed;

    [self createToolbarItems];
    NSToolbar* toolbar =
        [[NSToolbar alloc] initWithIdentifier:@"FiberWindowToolbar"];
    toolbar.delegate = self;
    toolbar.displayMode = NSToolbarDisplayModeIconOnly;
    toolbar.allowsUserCustomization = NO;
    toolbar.centeredItemIdentifiers =
        [NSSet setWithObject:kLocationItemIdentifier];
    _window.toolbar = toolbar;
    _window.toolbarStyle = NSWindowToolbarStyleUnified;

    NSView* content = _window.contentView;
    _progressBar = [[FiberProgressBar alloc]
        initWithFrame:NSMakeRect(0, NSHeight(content.bounds) - kProgressBarHeight,
                                 NSWidth(content.bounds), kProgressBarHeight)];
    _progressBar.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin;
    [content addSubview:_progressBar];

    _statusBubble = [[FiberStatusBubble alloc]
        initWithFrame:NSMakeRect(kStatusBubbleInset, kStatusBubbleInset, 0, 0)];
    _statusBubble.autoresizingMask = NSViewMaxXMargin | NSViewMaxYMargin;
    [content addSubview:_statusBubble];

    [self positionWindow];
  }
  return self;
}

- (void)createToolbarItems {
  _backItem = [self buttonItemWithIdentifier:kBackItemIdentifier
                                      symbol:@"chevron.backward"
                                       label:@"Back"
                                      action:@selector(goBack:)];
  _forwardItem = [self buttonItemWithIdentifier:kForwardItemIdentifier
                                         symbol:@"chevron.forward"
                                          label:@"Forward"
                                         action:@selector(goForward:)];
  _reloadItem = [self buttonItemWithIdentifier:kReloadItemIdentifier
                                        symbol:@"arrow.clockwise"
                                         label:@"Reload"
                                        action:@selector(reloadOrStop:)];

  _locationField = [[FiberLocationField alloc] initWithFrame:NSZeroRect];
  _locationField.target = self;
  _locationField.action = @selector(navigateToLocation:);
  _locationField.delegate = self;

  NSView* locationBar = [self capsuleContainingView:_locationField];
  [locationBar.heightAnchor constraintEqualToConstant:kLocationBarHeight]
      .active = YES;
  // Grow toward the max width, but let the toolbar squeeze it down to the min.
  [locationBar.widthAnchor constraintGreaterThanOrEqualToConstant:240].active =
      YES;
  [locationBar.widthAnchor constraintLessThanOrEqualToConstant:800].active =
      YES;
  NSLayoutConstraint* preferredWidth =
      [locationBar.widthAnchor constraintEqualToConstant:800];
  preferredWidth.priority = NSLayoutPriorityDefaultLow;
  preferredWidth.active = YES;

  _locationItem =
      [[NSToolbarItem alloc] initWithItemIdentifier:kLocationItemIdentifier];
  _locationItem.view = locationBar;
  _locationItem.label = @"Address";
  _locationItem.visibilityPriority = NSToolbarItemVisibilityPriorityHigh;
}

// Toolbar items with custom views get no background of their own, so match
// the Liquid Glass capsules of the standard items where available.
- (NSView*)capsuleContainingView:(NSView*)view {
  if (@available(macOS 26, *)) {
    NSGlassEffectView* glass = [[NSGlassEffectView alloc] init];
    glass.cornerRadius = kLocationBarHeight / 2;
    glass.contentView = view;
    return glass;
  }
  NSBox* box = [[NSBox alloc] init];
  box.boxType = NSBoxCustom;
  box.borderWidth = 0;
  box.cornerRadius = kLocationBarHeight / 2;
  box.fillColor = [NSColor.labelColor colorWithAlphaComponent:0.06];
  box.contentViewMargins = NSZeroSize;
  box.contentView = view;
  return box;
}

- (NSToolbarItem*)buttonItemWithIdentifier:(NSToolbarItemIdentifier)identifier
                                    symbol:(NSString*)symbol
                                     label:(NSString*)label
                                    action:(SEL)action {
  NSToolbarItem* item =
      [[NSToolbarItem alloc] initWithItemIdentifier:identifier];
  item.image = [NSImage imageWithSystemSymbolName:symbol
                         accessibilityDescription:label];
  item.label = label;
  item.toolTip = label;
  item.target = self;
  item.action = action;
  item.bordered = YES;
  item.navigational = YES;
  // Enabled state is pushed from -updateWithURL:..., not polled.
  item.autovalidates = NO;
  return item;
}

// Cascades from the current key window, if any; otherwise centers.
- (void)positionWindow {
  NSWindow* keyWindow = NSApp.keyWindow;
  if (!keyWindow) {
    [_window center];
    return;
  }
  const NSPoint topLeft =
      NSMakePoint(NSMinX(keyWindow.frame), NSMaxY(keyWindow.frame));
  [_window cascadeTopLeftFromPoint:[_window cascadeTopLeftFromPoint:topLeft]];
}

- (void)setWebContentsView:(NSView*)view {
  NSView* content = _window.contentView;
  view.frame = content.bounds;
  view.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
  // Below the progress bar and status bubble.
  [content addSubview:view positioned:NSWindowBelow relativeTo:nil];
}

- (void)updateWithURL:(NSString*)url
        displayString:(NSString*)displayString
                title:(NSString*)title
            canGoBack:(BOOL)canGoBack
         canGoForward:(BOOL)canGoForward
            isLoading:(BOOL)isLoading {
  _window.title = title.length ? title : @"Fiber";
  [_locationField setURL:url displayString:displayString];
  _backItem.enabled = canGoBack;
  _forwardItem.enabled = canGoForward;
  NSString* reloadLabel = isLoading ? @"Stop" : @"Reload";
  _reloadItem.image = [NSImage
      imageWithSystemSymbolName:isLoading ? @"xmark" : @"arrow.clockwise"
       accessibilityDescription:reloadLabel];
  _reloadItem.label = reloadLabel;
  _reloadItem.toolTip = reloadLabel;
}

- (void)setLoading:(BOOL)loading progress:(double)progress {
  if (loading) {
    [_progressBar setProgress:progress];
  } else {
    [_progressBar finish];
  }
}

- (void)setStatusText:(NSString*)text {
  [_statusBubble setText:text];
}

- (void)focusLocationBar {
  if (_locationField.editing) {
    [_locationField.currentEditor selectAll:nil];
  } else {
    [_window makeFirstResponder:_locationField];
  }
}

- (void)detachOwner {
  _owner = nullptr;
}

// Toolbar actions.

- (void)goBack:(id)sender {
  if (_owner) {
    _owner->GoBack();
  }
}

- (void)goForward:(id)sender {
  if (_owner) {
    _owner->GoForward();
  }
}

- (void)reloadOrStop:(id)sender {
  if (_owner) {
    _owner->ReloadOrStop();
  }
}

- (void)navigateToLocation:(id)sender {
  if (_owner) {
    _owner->NavigateToInput(base::SysNSStringToUTF8(_locationField.stringValue));
  }
}

// Chrome's main menu sends -commandDispatch: with the command ID as the tag.
// As the window delegate we're in the responder chain ahead of Chrome's
// AppController, so menu items act on this window while it's key.

- (void)commandDispatch:(id)sender {
  if (!_owner) {
    return;
  }
  switch ([sender tag]) {
    case IDC_BACK:
      _owner->GoBack();
      break;
    case IDC_FORWARD:
      _owner->GoForward();
      break;
    case IDC_RELOAD:
    case IDC_STOP:
      _owner->ReloadOrStop();
      break;
    case IDC_FOCUS_LOCATION:
      [self focusLocationBar];
      break;
    case IDC_NEW_TAB:
    case IDC_NEW_WINDOW:
      _owner->NewWindow();
      break;
    case IDC_CLOSE_TAB:
    case IDC_CLOSE_WINDOW:
      _owner->Close();
      break;
  }
}

- (BOOL)validateUserInterfaceItem:(id<NSValidatedUserInterfaceItem>)item {
  if (item.action != @selector(commandDispatch:)) {
    return YES;
  }
  switch (item.tag) {
    case IDC_BACK:
      return _backItem.enabled;
    case IDC_FORWARD:
      return _forwardItem.enabled;
    case IDC_RELOAD:
    case IDC_STOP:
    case IDC_FOCUS_LOCATION:
    case IDC_NEW_TAB:
    case IDC_NEW_WINDOW:
    case IDC_CLOSE_TAB:
    case IDC_CLOSE_WINDOW:
      return YES;
    default:
      // Everything else in Chrome's menus assumes a Chrome Browser window.
      return NO;
  }
}

// NSToolbarDelegate:

- (NSArray<NSToolbarItemIdentifier>*)toolbarDefaultItemIdentifiers:
    (NSToolbar*)toolbar {
  return @[
    kBackItemIdentifier, kForwardItemIdentifier, kReloadItemIdentifier,
    kLocationItemIdentifier
  ];
}

- (NSArray<NSToolbarItemIdentifier>*)toolbarAllowedItemIdentifiers:
    (NSToolbar*)toolbar {
  return [self toolbarDefaultItemIdentifiers:toolbar];
}

- (NSToolbarItem*)toolbar:(NSToolbar*)toolbar
        itemForItemIdentifier:(NSToolbarItemIdentifier)identifier
    willBeInsertedIntoToolbar:(BOOL)flag {
  if ([identifier isEqualToString:kBackItemIdentifier]) {
    return _backItem;
  }
  if ([identifier isEqualToString:kForwardItemIdentifier]) {
    return _forwardItem;
  }
  if ([identifier isEqualToString:kReloadItemIdentifier]) {
    return _reloadItem;
  }
  if ([identifier isEqualToString:kLocationItemIdentifier]) {
    return _locationItem;
  }
  return nil;
}

// NSTextFieldDelegate:

// Escape reverts the location field's edits; a second Escape returns focus to
// the page.
- (BOOL)control:(NSControl*)control
               textView:(NSTextView*)textView
    doCommandBySelector:(SEL)selector {
  if (control != _locationField || selector != @selector(cancelOperation:)) {
    return NO;
  }
  if (_locationField.hasEdits) {
    [_locationField revertEdits];
  } else if (_owner) {
    _owner->FocusWebContents();
  }
  return YES;
}

// NSWindowDelegate:

- (void)windowWillClose:(NSNotification*)notification {
  if (_owner) {
    _owner->OnNativeWindowClosing();
  }
}

@end
