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

// Swipes between pages, the page following the fingers, in place of Chrome's
// HistorySwiper and its arrows. Swapped in by
// patches/chromium/chrome-browser-renderer_host-chrome_render_widget_host_view_mac_delegate.mm.patch.
@interface FiberHistorySwiper : NSObject

- (instancetype)initWithDelegate:(id<HistorySwiperDelegate>)delegate;

@property(nonatomic, weak) id<HistorySwiperDelegate> delegate;

// Returns whether the swipe consumed `event`, which then doesn't go to the
// page.
- (BOOL)handleEvent:(NSEvent*)event;
- (void)rendererHandledGestureScrollEvent:(const blink::WebGestureEvent&)event
                                 consumed:(BOOL)consumed;
- (void)onOverscrolled:(const ui::DidOverscrollParams&)params;

// Unused: AppKit's swipe tracking follows the gesture, where Chrome tracks
// trackpad touches itself.
- (void)touchesBeganWithEvent:(NSEvent*)event;
- (void)touchesMovedWithEvent:(NSEvent*)event;
- (void)touchesCancelledWithEvent:(NSEvent*)event;
- (void)touchesEndedWithEvent:(NSEvent*)event;

@end

#endif  // FIBER_BROWSER_SWIPE_FIBER_HISTORY_SWIPER_H_
