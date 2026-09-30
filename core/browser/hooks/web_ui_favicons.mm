#include "fiber/browser/hooks/web_ui_favicons.h"

#include <cmath>

#import "FiberBridge/FiberBuiltInPageFavicon.h"
#include "base/apple/foundation_util.h"
#include "base/memory/ref_counted_memory.h"
#include "base/strings/sys_string_conversions.h"
#include "ui/gfx/favicon_size.h"

namespace fiber {

scoped_refptr<base::RefCountedMemory> GetWebUIFavicon(
    const GURL& page_url,
    ui::ResourceScaleFactor scale_factor) {
  if (!HasFiberFavicon(page_url)) {
    return nullptr;
  }
  const int pixel_size = std::lround(
      gfx::kFaviconSize * ui::GetScaleForResourceScaleFactor(scale_factor));
  NSData* png = [FiberBuiltInPageFavicon
      pngForHost:base::SysUTF8ToNSString(page_url.host())
       pixelSize:pixel_size];
  return base::MakeRefCounted<base::RefCountedBytes>(
      base::apple::NSDataToSpan(png));
}

}  // namespace fiber
