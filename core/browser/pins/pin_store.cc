#include "fiber/browser/pins/pin_store.h"

#include <algorithm>
#include <utility>

#include "base/base64.h"
#include "base/strings/utf_string_conversions.h"
#include "base/values.h"
#include "chrome/browser/profiles/profile.h"
#include "components/pref_registry/pref_registry_syncable.h"
#include "components/prefs/pref_service.h"
#include "third_party/skia/include/core/SkBitmap.h"
#include "ui/gfx/codec/png_codec.h"
#include "ui/gfx/favicon_size.h"
#include "ui/gfx/image/image_skia.h"
#include "ui/gfx/image/image_skia_rep.h"

namespace fiber {

namespace {

// A list of the pins, each {id, url, title, icon: a base64 PNG}.
constexpr char kPinsPref[] = "fiber.pins";

const void* const kUserDataKey = &kUserDataKey;

// The icon for Retina screens, or as close as it has, as a PNG.
std::vector<uint8_t> EncodeIcon(const gfx::Image& icon) {
  if (icon.IsEmpty()) {
    return {};
  }
  const gfx::ImageSkiaRep& rep = icon.ToImageSkia()->GetRepresentation(2.0f);
  if (rep.is_null()) {
    return {};
  }
  return gfx::PNGCodec::EncodeBGRASkBitmap(rep.GetBitmap(),
                                           /*discard_transparency=*/false)
      .value_or(std::vector<uint8_t>());
}

// A favicon's PNG at the scale its size implies.
gfx::Image DecodeIcon(const std::vector<uint8_t>& png) {
  if (png.empty()) {
    return gfx::Image();
  }
  SkBitmap bitmap = gfx::PNGCodec::Decode(png);
  if (bitmap.isNull()) {
    return gfx::Image();
  }
  const float scale =
      std::max(1.0f, static_cast<float>(bitmap.width()) / gfx::kFaviconSize);
  return gfx::Image(gfx::ImageSkia::CreateFromBitmap(bitmap, scale));
}

}  // namespace

Pin::Pin() = default;
Pin::Pin(const Pin&) = default;
Pin& Pin::operator=(const Pin&) = default;
Pin::~Pin() = default;

// static
PinStore* PinStore::FromProfile(Profile* profile) {
  if (!profile || profile->IsOffTheRecord()) {
    return nullptr;
  }
  auto* store = static_cast<PinStore*>(profile->GetUserData(kUserDataKey));
  if (!store) {
    auto owned = std::make_unique<PinStore>(profile);
    store = owned.get();
    profile->SetUserData(kUserDataKey, std::move(owned));
  }
  return store;
}

// static
void PinStore::RegisterProfilePrefs(user_prefs::PrefRegistrySyncable* registry) {
  registry->RegisterListPref(kPinsPref);
}

PinStore::PinStore(Profile* profile) : profile_(profile) {
  Load();
}

PinStore::~PinStore() = default;

const Pin* PinStore::Find(std::string_view id) const {
  auto it = std::ranges::find(pins_, id, &Pin::id);
  return it != pins_.end() ? &*it : nullptr;
}

Pin* PinStore::FindMutable(std::string_view id) {
  return const_cast<Pin*>(Find(id));
}

std::optional<size_t> PinStore::IndexOf(std::string_view id) const {
  auto it = std::ranges::find(pins_, id, &Pin::id);
  if (it == pins_.end()) {
    return std::nullopt;
  }
  return it - pins_.begin();
}

void PinStore::Add(Pin pin, size_t index) {
  if (pin.id.empty() || Find(pin.id)) {
    return;
  }
  pin.icon_png = EncodeIcon(pin.icon);
  pins_.insert(pins_.begin() + std::min(index, pins_.size()), std::move(pin));
  Changed();
}

void PinStore::Remove(std::string_view id) {
  if (std::erase_if(pins_, [id](const Pin& pin) { return pin.id == id; })) {
    Changed();
  }
}

void PinStore::Move(std::string_view id, size_t index) {
  std::optional<size_t> from = IndexOf(id);
  if (!from) {
    return;
  }
  const size_t to = std::min(index, pins_.size() - 1);
  if (to == *from) {
    return;
  }
  if (to > *from) {
    std::rotate(pins_.begin() + *from, pins_.begin() + *from + 1,
                pins_.begin() + to + 1);
  } else {
    std::rotate(pins_.begin() + to, pins_.begin() + *from,
                pins_.begin() + *from + 1);
  }
  Changed();
}

void PinStore::Update(std::string_view id,
                      const GURL& url,
                      const std::u16string& title,
                      const gfx::Image& icon) {
  Pin* pin = FindMutable(id);
  if (!pin) {
    return;
  }
  std::vector<uint8_t> icon_png = EncodeIcon(icon);
  const bool icon_changed = !icon_png.empty() && icon_png != pin->icon_png;
  if (url == pin->url && title == pin->title && !icon_changed) {
    return;
  }
  pin->url = url;
  pin->title = title;
  if (icon_changed) {
    pin->icon = icon;
    pin->icon_png = std::move(icon_png);
  }
  Changed();
}

void PinStore::AddObserver(Observer* observer) {
  observers_.AddObserver(observer);
}

void PinStore::RemoveObserver(Observer* observer) {
  observers_.RemoveObserver(observer);
}

void PinStore::Load() {
  for (const base::Value& value : profile_->GetPrefs()->GetList(kPinsPref)) {
    const base::DictValue* dict = value.GetIfDict();
    if (!dict) {
      continue;
    }
    const std::string* id = dict->FindString("id");
    const std::string* url = dict->FindString("url");
    if (!id || id->empty() || !url || Find(*id)) {
      continue;
    }
    Pin pin;
    pin.id = *id;
    pin.url = GURL(*url);
    if (const std::string* title = dict->FindString("title")) {
      pin.title = base::UTF8ToUTF16(*title);
    }
    if (const std::string* icon = dict->FindString("icon")) {
      pin.icon_png = base::Base64Decode(*icon).value_or(std::vector<uint8_t>());
      pin.icon = DecodeIcon(pin.icon_png);
    }
    pins_.push_back(std::move(pin));
  }
}

void PinStore::Changed() {
  base::ListValue list;
  for (const Pin& pin : pins_) {
    list.Append(base::DictValue()
                    .Set("id", pin.id)
                    .Set("url", pin.url.spec())
                    .Set("title", base::UTF16ToUTF8(pin.title))
                    .Set("icon", base::Base64Encode(pin.icon_png)));
  }
  profile_->GetPrefs()->SetList(kPinsPref, std::move(list));
  observers_.Notify(&Observer::OnPinsChanged);
}

}  // namespace fiber
