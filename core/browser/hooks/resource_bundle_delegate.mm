#include "fiber/browser/hooks/resource_bundle_delegate.h"

#import <Foundation/Foundation.h>
#import <ImageIO/ImageIO.h>

#include <cmath>
#include <map>
#include <optional>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

#include "base/apple/bridging.h"
#include "base/apple/scoped_cftyperef.h"
#include "base/base64.h"
#include "base/containers/span.h"
#include "base/files/file_path.h"
#include "base/memory/ref_counted_memory.h"
#include "base/no_destructor.h"
#include "base/strings/strcat.h"
#include "base/strings/string_number_conversions.h"
#include "base/strings/string_view_util.h"
#include "base/synchronization/lock.h"
#include "chrome/grit/chrome_unscaled_resources.h"
#include "chrome/grit/theme_resources.h"
#include "components/grit/components_scaled_resources.h"
#include "skia/ext/image_operations.h"
#include "skia/ext/skia_utils_mac.h"
#include "third_party/skia/include/core/SkBitmap.h"
#include "ui/base/resource/resource_scale_factor.h"
#include "ui/gfx/codec/png_codec.h"
#include "ui/gfx/image/image.h"
#include "ui/gfx/image/image_skia.h"
#include "ui/gfx/image/image_skia_rep.h"
#include "ui/webui/resources/grit/webui_resources.h"

namespace fiber {

namespace {

struct ProductLogo {
  // In points.
  int size;
  // An SVG rather than a PNG.
  bool svg = false;
};

// Chrome's product logos, which Fiber's app icon stands in for: among them
// chrome://version's wordmark (IDR_PRODUCT_LOGO) and the white logo WebUI
// toolbars show on dark pages.
std::optional<ProductLogo> GetProductLogo(int resource_id) {
  switch (resource_id) {
    case IDR_PRODUCT_LOGO_16:
      return ProductLogo{16};
    case IDR_PRODUCT_LOGO_32:
    case IDR_PRODUCT_LOGO:
    case IDR_PRODUCT_LOGO_WHITE:
      return ProductLogo{32};
    case IDR_PRODUCT_LOGO_64:
      return ProductLogo{64};
    case IDR_PRODUCT_LOGO_128:
      return ProductLogo{128};
    case IDR_PRODUCT_LOGO_256:
      return ProductLogo{256};
    case IDR_WEBUI_IMAGES_CHROME_LOGO_DARK_SVG:
      return ProductLogo{24, /*svg=*/true};
    default:
      return std::nullopt;
  }
}

// The app's icon, `pixels` square, scaled from the smallest image in app.icns
// at least that big. WebUI loads resources on the thread pool, so this uses
// ImageIO, which any thread may, rather than AppKit.
SkBitmap AppIconBitmap(int pixels) {
  NSURL* url = [NSBundle.mainBundle URLForResource:@"app"
                                     withExtension:@"icns"];
  if (!url) {
    return SkBitmap();
  }
  base::apple::ScopedCFTypeRef<CGImageSourceRef> source(
      CGImageSourceCreateWithURL(base::apple::NSToCFPtrCast(url), nullptr));
  if (!source) {
    return SkBitmap();
  }
  std::optional<size_t> best;
  int best_width = 0;
  for (size_t i = 0; i < CGImageSourceGetCount(source.get()); ++i) {
    NSDictionary* properties = base::apple::CFToNSOwnershipCast(
        CGImageSourceCopyPropertiesAtIndex(source.get(), i, nullptr));
    const int width = [properties[base::apple::CFToNSPtrCast(
        kCGImagePropertyPixelWidth)] intValue];
    if (!best || (width >= pixels
                      ? best_width < pixels || width < best_width
                      : width > best_width)) {
      best = i;
      best_width = width;
    }
  }
  if (!best) {
    return SkBitmap();
  }
  base::apple::ScopedCFTypeRef<CGImageRef> image(
      CGImageSourceCreateImageAtIndex(source.get(), *best, nullptr));
  SkBitmap bitmap = skia::CGImageToSkBitmap(image.get());
  if (bitmap.isNull() || bitmap.width() == pixels) {
    return bitmap;
  }
  return skia::ImageOperations::Resize(
      bitmap, skia::ImageOperations::RESIZE_BEST, pixels, pixels);
}

std::optional<std::vector<uint8_t>> AppIconPNG(int pixels) {
  SkBitmap bitmap = AppIconBitmap(pixels);
  if (bitmap.isNull()) {
    return std::nullopt;
  }
  return gfx::PNGCodec::EncodeBGRASkBitmap(bitmap,
                                           /*discard_transparency=*/false);
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
    std::optional<ProductLogo> logo = GetProductLogo(resource_id);
    if (!logo || logo->svg) {
      return gfx::Image();
    }
    gfx::ImageSkia image;
    for (int scale : {1, 2}) {
      SkBitmap bitmap = AppIconBitmap(logo->size * scale);
      if (!bitmap.isNull()) {
        image.AddRepresentation(gfx::ImageSkiaRep(bitmap, scale));
      }
    }
    return gfx::Image(image);
  }

  gfx::Image GetNativeImageNamed(int resource_id) override {
    return GetImageNamed(resource_id);
  }

  bool HasDataResource(int resource_id) const override {
    return GetProductLogo(resource_id).has_value();
  }

  scoped_refptr<base::RefCountedMemory> LoadDataResourceBytes(
      int resource_id,
      ui::ResourceScaleFactor scale_factor) override {
    return LogoData(resource_id, scale_factor);
  }

  std::optional<std::string> LoadDataResourceString(int resource_id) override {
    scoped_refptr<base::RefCountedMemory> data =
        LogoData(resource_id, ui::kScaleFactorNone);
    if (!data) {
      return std::nullopt;
    }
    return std::string(base::as_string_view(base::span<const uint8_t>(*data)));
  }

  bool GetRawDataResource(int resource_id,
                          ui::ResourceScaleFactor scale_factor,
                          std::string_view* value) const override {
    scoped_refptr<base::RefCountedMemory> data =
        LogoData(resource_id, scale_factor);
    if (!data) {
      return false;
    }
    *value = base::as_string_view(base::span<const uint8_t>(*data));
    return true;
  }

  bool GetLocalizedString(int message_id,
                          std::u16string* value) const override {
    return false;
  }

 private:
  // A logo's file at `scale_factor` (1x for an unscaled PNG). An SVG wraps a
  // PNG sharp at 3x. Kept, since GetRawDataResource() hands out views of it.
  scoped_refptr<base::RefCountedMemory> LogoData(
      int resource_id,
      ui::ResourceScaleFactor scale_factor) const {
    std::optional<ProductLogo> logo = GetProductLogo(resource_id);
    if (!logo) {
      return nullptr;
    }
    if (logo->svg) {
      scale_factor = ui::kScaleFactorNone;
    }
    base::AutoLock lock(lock_);
    scoped_refptr<base::RefCountedMemory>& data =
        data_[{resource_id, scale_factor}];
    if (data) {
      return data;
    }
    const int pixels =
        logo->svg ? logo->size * 3
                  : static_cast<int>(std::lround(
                        logo->size *
                        ui::GetScaleForResourceScaleFactor(scale_factor)));
    std::optional<std::vector<uint8_t>> png = AppIconPNG(pixels);
    if (!png) {
      return nullptr;
    }
    if (logo->svg) {
      const std::string size = base::NumberToString(logo->size);
      data = base::MakeRefCounted<base::RefCountedString>(base::StrCat(
          {"<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"", size,
           "\" height=\"", size, "\"><image width=\"", size, "\" height=\"",
           size, "\" href=\"data:image/png;base64,", base::Base64Encode(*png),
           "\"/></svg>"}));
    } else {
      data = base::MakeRefCounted<base::RefCountedBytes>(std::move(*png));
    }
    return data;
  }

  mutable base::Lock lock_;
  mutable std::map<std::pair<int, ui::ResourceScaleFactor>,
                   scoped_refptr<base::RefCountedMemory>>
      data_;
};

}  // namespace

ui::ResourceBundle::Delegate* GetResourceBundleDelegate() {
  static base::NoDestructor<ProductLogoDelegate> delegate;
  return delegate.get();
}

}  // namespace fiber
