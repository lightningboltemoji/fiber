#ifndef FIBER_BROWSER_SWIPE_FIBER_HISTORY_SWIPER_H_
#define FIBER_BROWSER_SWIPE_FIBER_HISTORY_SWIPER_H_

#import <AppKit/AppKit.h>

#import "chrome/browser/renderer_host/chrome_render_widget_host_view_mac_history_swiper.h"

namespace blink {
class WebGestureEvent;
}

namespace ui {
struct DidOverscrollParams;
}

// Swiping between pages in a Fiber window: two fingers on a trackpad, or one
// on a Magic Mouse. The page follows the fingers like a sheet of paper, as in
// Safari (see FiberWindow's -beginHistorySwipeInDirection:snapshot:), in
// place of Chrome's HistorySwiper and its arrows. Its interface is
// HistorySwiper's, for ChromeRenderWidgetHostViewMacDelegate (see
// patches/chromium/chrome-browser-renderer_host-chrome_render_widget_host_view_mac_delegate.mm.patch).
//
// Like Chrome's, a scroll only becomes a swipe once the page has passed it up
// (it didn't scroll, and its overscroll-behavior lets it through) and it's
// mostly horizontal. From then on AppKit tracks it
// (-[NSEvent trackSwipeEventWithOptions:…]), including the animation after the
// user lets go, which carries on from the fingers' speed. Chrome only does
// that for the Magic Mouse; it tracks trackpad touches itself, for a
// progress bar that doesn't need the physics.
@interface FiberHistorySwiper : NSObject

- (instancetype)initWithDelegate:(id<HistorySwiperDelegate>)delegate;

@property(nonatomic, weak) id<HistorySwiperDelegate> delegate;

// Returns whether the swipe consumed `event`, which then doesn't go to the
// page.
- (BOOL)handleEvent:(NSEvent*)event;
- (void)rendererHandledGestureScrollEvent:(const blink::WebGestureEvent&)event
                                 consumed:(BOOL)consumed;
- (void)onOverscrolled:(const ui::DidOverscrollParams&)params;

// Unused: AppKit's swipe tracking follows the gesture.
- (void)touchesBeganWithEvent:(NSEvent*)event;
- (void)touchesMovedWithEvent:(NSEvent*)event;
- (void)touchesCancelledWithEvent:(NSEvent*)event;
- (void)touchesEndedWithEvent:(NSEvent*)event;

@end

#endif  // FIBER_BROWSER_SWIPE_FIBER_HISTORY_SWIPER_H_
