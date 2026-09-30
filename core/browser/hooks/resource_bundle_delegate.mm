#include "fiber/browser/hooks/resource_bundle_delegate.h"

#import <Foundation/Foundation.h>

#include <cmath>
#include <map>
#include <optional>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

#import "FiberBridge/FiberBuiltInPageFavicon.h"
#import "FiberBridge/FiberProfileSwitcher.h"
#include "base/apple/foundation_util.h"
#include "base/containers/flat_map.h"
#include "base/containers/span.h"
#include "base/files/file_path.h"
#include "base/memory/ref_counted_memory.h"
#include "base/no_destructor.h"
#include "base/strings/string_view_util.h"
#include "chrome/browser/profiles/profile_avatar_icon_util.h"
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

// The size in points of Chrome's modern default avatars, which Fiber's own
// stand in for, like the rest of its default avatars.
constexpr int kAvatarSize = 96;

// The default avatar a resource is, as Chrome numbers them.
std::optional<size_t> AvatarIndex(int resource_id) {
  static const base::NoDestructor<base::flat_map<int, size_t>> indices([] {
    std::vector<std::pair<int, size_t>> indices;
    for (size_t i = 0; i < profiles::GetDefaultAvatarIconCount(); ++i) {
      indices.emplace_back(profiles::GetDefaultAvatarIconResourceIDAtIndex(i),
                           i);
    }
    indices.emplace_back(profiles::GetPlaceholderAvatarIconResourceID(),
                         profiles::GetPlaceholderAvatarIndex());
    return base::flat_map<int, size_t>(std::move(indices));
  }());
  auto it = indices->find(resource_id);
  if (it == indices->end()) {
    return std::nullopt;
  }
  return it->second;
}

// The size in points of a resource Fiber draws, or 0 for one it doesn't.
int FiberResourceSize(int resource_id) {
  if (const int size = ProductLogoSize(resource_id)) {
    return size;
  }
  return AvatarIndex(resource_id) ? kAvatarSize : 0;
}

// Fiber's mark, `pixels` square, as the New Tab page's favicon draws it: in one
// gray, which reads on light and dark pages alike.
scoped_refptr<base::RefCountedMemory> MarkPNG(int pixels) {
  return base::MakeRefCounted<base::RefCountedBytes>(
      base::apple::NSDataToSpan([FiberBuiltInPageFavicon pngForHost:@"newtab"
                                                          pixelSize:pixels]));
}

scoped_refptr<base::RefCountedMemory> AvatarPNG(size_t index, int pixels) {
  return base::MakeRefCounted<base::RefCountedBytes>(base::apple::NSDataToSpan(
      [FiberProfileAvatars pngForAvatarIndex:index pixelSize:pixels]));
}

// Fiber's own for Chrome's product logos and default profile avatars.
class FiberResourceDelegate : public ui::ResourceBundle::Delegate {
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
          FiberPNG(resource_id, scale_factor);
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
    return FiberResourceSize(resource_id) != 0;
  }

  scoped_refptr<base::RefCountedMemory> LoadDataResourceBytes(
      int resource_id,
      ui::ResourceScaleFactor scale_factor) override {
    return FiberPNG(resource_id, scale_factor);
  }

  std::optional<std::string> LoadDataResourceString(int resource_id) override {
    return std::nullopt;
  }

  bool GetRawDataResource(int resource_id,
                          ui::ResourceScaleFactor scale_factor,
                          std::string_view* value) const override {
    scoped_refptr<base::RefCountedMemory> png =
        FiberPNG(resource_id, scale_factor);
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
  // A resource Fiber draws, as a PNG at `scale_factor` (1x for an unscaled
  // one), kept since GetRawDataResource() hands out views of it. Only on the
  // main thread, where the UI draws and Chrome asks for these.
  scoped_refptr<base::RefCountedMemory> FiberPNG(
      int resource_id,
      ui::ResourceScaleFactor scale_factor) const {
    const int size = FiberResourceSize(resource_id);
    if (!size || !NSThread.isMainThread) {
      return nullptr;
    }
    const int pixels = static_cast<int>(std::lround(
        size * ui::GetScaleForResourceScaleFactor(scale_factor)));
    const std::optional<size_t> avatar = AvatarIndex(resource_id);
    // Every product logo is the mark.
    const int key = avatar ? resource_id : 0;
    scoped_refptr<base::RefCountedMemory>& png = pngs_[{key, pixels}];
    if (!png) {
      png = avatar ? AvatarPNG(*avatar, pixels) : MarkPNG(pixels);
    }
    return png;
  }

  // By resource (0 for the mark) and size in pixels.
  mutable std::map<std::pair<int, int>, scoped_refptr<base::RefCountedMemory>>
      pngs_;
};

}  // namespace

ui::ResourceBundle::Delegate* GetResourceBundleDelegate() {
  static base::NoDestructor<FiberResourceDelegate> delegate;
  return delegate.get();
}

}  // namespace fiber
