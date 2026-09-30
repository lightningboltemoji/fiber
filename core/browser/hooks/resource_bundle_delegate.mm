#include "fiber/browser/hooks/resource_bundle_delegate.h"

#import <Foundation/Foundation.h>

#include <cmath>
#include <map>
#include <optional>
#include <string>
#include <string_view>
#include <utility>

#import "FiberBridge/FiberBuiltInPageFavicon.h"
#include "base/apple/foundation_util.h"
#include "base/containers/span.h"
#include "base/files/file_path.h"
#include "base/memory/ref_counted_memory.h"
#include "base/no_destructor.h"
#include "base/strings/string_view_util.h"
#include "chrome/grit/chrome_unscaled_resources.h"
#include "chrome/grit/theme_resources.h"
#include "components/grit/components_scaled_resources.h"
#include "third_party/skia/include/core/SkBitmap.h"
#include "ui/base/resource/resource_scale_factor.h"
#include "ui/gfx/codec/png_codec.h"
#include "ui/gfx/image/image.h"
#include "ui/gfx/image/image_skia.h"
#include "ui/gfx/image/image_skia_rep.h"

namespace fiber {

namespace {

// The size in points of each of Chrome's product logos, which Fiber's mark
// stands in for, or 0 for any other resource. chrome://version's
// (IDR_PRODUCT_LOGO, and its white variant for dark pages) is a wordmark.
int ProductLogoSize(int resource_id) {
  switch (resource_id) {
    case IDR_PRODUCT_LOGO_16:
      return 16;
    case IDR_PRODUCT_LOGO_32:
    case IDR_PRODUCT_LOGO:
    case IDR_PRODUCT_LOGO_WHITE:
      return 32;
    case IDR_PRODUCT_LOGO_64:
      return 64;
    case IDR_PRODUCT_LOGO_128:
      return 128;
    case IDR_PRODUCT_LOGO_256:
      return 256;
    default:
      return 0;
  }
}

// Fiber's mark, `pixels` square, as the New Tab page's favicon draws it: in one
// gray, which reads on light and dark pages alike.
scoped_refptr<base::RefCountedMemory> MarkPNG(int pixels) {
  return base::MakeRefCounted<base::RefCountedBytes>(
      base::apple::NSDataToSpan([FiberBuiltInPageFavicon pngForHost:@"newtab"
                                                          pixelSize:pixels]));
}

class ProductLogoDelegate : public ui::ResourceBundle::Delegate {
 public:
  // ui::ResourceBundle::Delegate:
  base::FilePath GetPathForResourcePack(
      const base::FilePath& pack_path,
      ui::ResourceScaleFactor scale_factor) override {
    return pack_path;
  }

  gfx::Image GetImageNamed(int resource_id) override {
    gfx::ImageSkia image;
    for (ui::ResourceScaleFactor scale_factor :
         {ui::k100Percent, ui::k200Percent}) {
      scoped_refptr<base::RefCountedMemory> png =
          LogoPNG(resource_id, scale_factor);
      if (!png) {
        return gfx::Image();
      }
      image.AddRepresentation(gfx::ImageSkiaRep(
          gfx::PNGCodec::Decode(base::span<const uint8_t>(*png)),
          ui::GetScaleForResourceScaleFactor(scale_factor)));
    }
    return gfx::Image(image);
  }

  gfx::Image GetNativeImageNamed(int resource_id) override {
    return GetImageNamed(resource_id);
  }

  bool HasDataResource(int resource_id) const override {
    return ProductLogoSize(resource_id) != 0;
  }

  scoped_refptr<base::RefCountedMemory> LoadDataResourceBytes(
      int resource_id,
      ui::ResourceScaleFactor scale_factor) override {
    return LogoPNG(resource_id, scale_factor);
  }

  std::optional<std::string> LoadDataResourceString(int resource_id) override {
    return std::nullopt;
  }

  bool GetRawDataResource(int resource_id,
                          ui::ResourceScaleFactor scale_factor,
                          std::string_view* value) const override {
    scoped_refptr<base::RefCountedMemory> png =
        LogoPNG(resource_id, scale_factor);
    if (!png) {
      return false;
    }
    *value = base::as_string_view(base::span<const uint8_t>(*png));
    return true;
  }

  bool GetLocalizedString(int message_id,
                          std::u16string* value) const override {
    return false;
  }

 private:
  // A product logo as a PNG at `scale_factor` (1x for an unscaled one). Kept,
  // since GetRawDataResource() hands out views of it. The UI draws it, so off
  // the main thread there's none; Chrome asks for its logos on the UI thread.
  scoped_refptr<base::RefCountedMemory> LogoPNG(
      int resource_id,
      ui::ResourceScaleFactor scale_factor) const {
    const int size = ProductLogoSize(resource_id);
    if (!size || !NSThread.isMainThread) {
      return nullptr;
    }
    const int pixels = static_cast<int>(std::lround(
        size * ui::GetScaleForResourceScaleFactor(scale_factor)));
    scoped_refptr<base::RefCountedMemory>& png = pngs_[pixels];
    if (!png) {
      png = MarkPNG(pixels);
    }
    return png;
  }

  // By size in pixels.
  mutable std::map<int, scoped_refptr<base::RefCountedMemory>> pngs_;
};

}  // namespace

ui::ResourceBundle::Delegate* GetResourceBundleDelegate() {
  static base::NoDestructor<ProductLogoDelegate> delegate;
  return delegate.get();
}

}  // namespace fiber
