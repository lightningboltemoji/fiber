#import "fiber/browser/swipe/fiber_history_swiper.h"

#include <cmath>

#include "fiber/browser/window/fiber_browser_window.h"
#include "third_party/blink/public/common/input/web_gesture_event.h"
#include "ui/events/blink/did_overscroll_params.h"
#include "ui/gfx/native_ui_types.h"

namespace {

// Scrolling this far up or down before the gesture turns horizontal makes it a
// scroll, not a swipe.
constexpr CGFloat kVerticalScrollDistance = 10;

}  // namespace

@implementation FiberHistorySwiper {
  // Whether the page passed up the gesture's first scroll…
  BOOL _firstScrollUnconsumed;
  // …and let it overscroll sideways (its overscroll-behavior allows it). A
  // swipe needs both.
  BOOL _overscrollTriggeredByRenderer;
  // Set from the gesture's scroll-begin until the page reports on its first
  // scroll.
  BOOL _waitingForFirstGestureScroll;
  // How far the gesture has scrolled.
  NSSize _scrollDelta;
  // The gesture can't become a swipe.
  BOOL _ruledOut;
  // AppKit is tracking the gesture as a swipe.
  BOOL _swiping;
}

@synthesize delegate = _delegate;

- (instancetype)initWithDelegate:(id<HistorySwiperDelegate>)delegate {
  if ((self = [super init])) {
    _delegate = delegate;
  }
  return self;
}

- (BOOL)handleEvent:(NSEvent*)event {
  if (event.type != NSEventTypeScrollWheel) {
    return NO;
  }
  if (event.phase == NSEventPhaseBegan) {
    _scrollDelta = NSZeroSize;
    _ruledOut = NO;
    _firstScrollUnconsumed = NO;
    _overscrollTriggeredByRenderer = NO;
  }
  if (_swiping) {
    return YES;
  }
  // Only a gesture's own scrolls start a swipe: not a mouse wheel's (no
  // phase), nor momentum after the fingers lift.
  if (event.phase != NSEventPhaseChanged || _ruledOut) {
    return NO;
  }

  _scrollDelta.width += event.scrollingDeltaX;
  _scrollDelta.height += event.scrollingDeltaY;
  if (std::abs(_scrollDelta.height) >= std::abs(_scrollDelta.width)) {
    _ruledOut = std::abs(_scrollDelta.height) > kVerticalScrollDistance;
    return NO;
  }

  if (!NSEvent.swipeTrackingFromScrollEventsEnabled ||
      ![_delegate shouldAllowHistorySwiping] || !_firstScrollUnconsumed ||
      !_overscrollTriggeredByRenderer) {
    return NO;
  }

  // Scrolling right goes back (fingers moving right, with natural scrolling).
  history_swiper::NavigationDirection direction =
      _scrollDelta.width > 0 ? history_swiper::kBackwards
                             : history_swiper::kForwards;
  if (![_delegate canNavigateInDirection:direction onWindow:event.window] ||
      !fiber::FiberBrowserWindow::FromNativeWindow(
          gfx::NativeWindow(event.window))) {
    _ruledOut = YES;
    return NO;
  }
  [self trackSwipe:event direction:direction];
  return YES;
}

- (void)trackSwipe:(NSEvent*)event
         direction:(history_swiper::NavigationDirection)direction {
  _swiping = YES;
  const bool back = direction == history_swiper::kBackwards;
  if (back) {
    [_delegate backwardsSwipeNavigationLikely];
  }

  NSWindow* nsWindow = event.window;
  __weak FiberHistorySwiper* weakSelf = self;
  __block BOOL began = NO;
  // Whether the user let go far enough (or fast enough) to go to the other
  // page, rather than back.
  __block BOOL landed = NO;
  // Locked to the direction it starts in, so swiping back past the start
  // doesn't turn it around. AppKit carries the amount on to 0 or ±1 after the
  // user lets go, then completes.
  [event trackSwipeEventWithOptions:NSEventSwipeTrackingLockDirection
           dampenAmountThresholdMin:-1
                                max:1
                       usingHandler:^(CGFloat gestureAmount, NSEventPhase phase,
                                      BOOL isComplete, BOOL* stop) {
                         FiberHistorySwiper* strongSelf = weakSelf;
                         fiber::FiberBrowserWindow* window =
                             fiber::FiberBrowserWindow::FromNativeWindow(
                                 gfx::NativeWindow(nsWindow));
                         if (!window) {
                           *stop = YES;
                           if (strongSelf) {
                             strongSelf->_swiping = NO;
                           }
                           return;
                         }
                         if (!began) {
                           began = YES;
                           window->BeginHistorySwipe(back);
                         }
                         if (phase == NSEventPhaseEnded) {
                           landed = YES;
                         } else if (phase == NSEventPhaseCancelled) {
                           landed = NO;
                         }
                         window->UpdateHistorySwipe(std::abs(gestureAmount));
                         if (!isComplete && strongSelf) {
                           return;
                         }
                         // The page is gone (a crash, say), or the swipe is
                         // done: going now, once it's carried the page off,
                         // so the page doesn't change under the fingers.
                         *stop = YES;
                         const bool navigating = landed && strongSelf;
                         window->EndHistorySwipe(navigating);
                         if (strongSelf) {
                           strongSelf->_swiping = NO;
                         }
                         if (navigating) {
                           [strongSelf.delegate
                               navigateInDirection:direction
                                          onWindow:nsWindow];
                         }
                       }];
}

- (void)rendererHandledGestureScrollEvent:(const blink::WebGestureEvent&)event
                                 consumed:(BOOL)consumed {
  switch (event.GetType()) {
    case blink::WebInputEvent::Type::kGestureScrollBegin:
      if (event.data.scroll_begin.synthetic ||
          event.data.scroll_begin.inertial_phase ==
              blink::WebGestureEvent::InertialPhaseState::kMomentum) {
        return;
      }
      _waitingForFirstGestureScroll = YES;
      break;
    case blink::WebInputEvent::Type::kGestureScrollUpdate:
      if (_waitingForFirstGestureScroll) {
        _firstScrollUnconsumed = !consumed;
      }
      _waitingForFirstGestureScroll = NO;
      break;
    default:
      break;
  }
}

- (void)onOverscrolled:(const ui::DidOverscrollParams&)params {
  _overscrollTriggeredByRenderer =
      params.overscroll_behavior.PropagatesXScroll();
}

- (void)touchesBeganWithEvent:(NSEvent*)event {
}

- (void)touchesMovedWithEvent:(NSEvent*)event {
}

- (void)touchesCancelledWithEvent:(NSEvent*)event {
}

- (void)touchesEndedWithEvent:(NSEvent*)event {
}

@end
