#include "fiber/browser/pins/pin_store.h"

#include <algorithm>
#include <utility>

#include "base/base64.h"
#include "base/strings/utf_string_conversions.h"
#include "base/uuid.h"
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

// A list of the pins and shelves' pages, each {id, url, title, icon: a base64
// PNG, and shelf: its shelf's ID, if it's on one}.
constexpr char kPinsPref[] = "fiber.pins";
// A list of the shelves, each {id, name}.
constexpr char kShelvesPref[] = "fiber.shelves";

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
  registry->RegisterListPref(kShelvesPref);
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

std::vector<const Pin*> PinStore::PinsOn(std::string_view shelf_id) const {
  const auto [start, end] = RangeOf(shelf_id);
  std::vector<const Pin*> pins;
  for (size_t i = start; i < end; ++i) {
    pins.push_back(&pins_[i]);
  }
  return pins;
}

std::optional<size_t> PinStore::IndexOf(std::string_view id) const {
  auto it = std::ranges::find(pins_, id, &Pin::id);
  if (it == pins_.end()) {
    return std::nullopt;
  }
  return it - pins_.begin();
}

std::optional<size_t> PinStore::PositionOf(std::string_view id) const {
  std::optional<size_t> index = IndexOf(id);
  if (!index) {
    return std::nullopt;
  }
  return *index - RangeOf(pins_[*index].shelf_id).first;
}

std::pair<size_t, size_t> PinStore::RangeOf(std::string_view shelf_id) const {
  // The pins come first, then each shelf's pages in the shelves' order.
  auto rank = [this](std::string_view id) -> size_t {
    if (id.empty()) {
      return 0;
    }
    return std::ranges::find(shelves_, id, &Shelf::id) - shelves_.begin() + 1;
  };
  const size_t shelf_rank = rank(shelf_id);
  size_t start = 0;
  while (start < pins_.size() && rank(pins_[start].shelf_id) < shelf_rank) {
    ++start;
  }
  size_t end = start;
  while (end < pins_.size() && pins_[end].shelf_id == shelf_id) {
    ++end;
  }
  return {start, end};
}

void PinStore::Add(Pin pin, size_t position) {
  if (pin.id.empty() || Find(pin.id) ||
      (!pin.shelf_id.empty() && !FindShelf(pin.shelf_id))) {
    return;
  }
  pin.icon_png = EncodeIcon(pin.icon);
  const auto [start, end] = RangeOf(pin.shelf_id);
  pins_.insert(pins_.begin() + start + std::min(position, end - start),
               std::move(pin));
  Changed();
}

void PinStore::Remove(std::string_view id) {
  if (std::erase_if(pins_, [id](const Pin& pin) { return pin.id == id; })) {
    Changed();
  }
}

void PinStore::Move(std::string_view id, size_t position) {
  std::optional<size_t> from = IndexOf(id);
  if (!from) {
    return;
  }
  const auto [start, end] = RangeOf(pins_[*from].shelf_id);
  const size_t to = start + std::min(position, end - start - 1);
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

void PinStore::MoveToShelf(std::string_view id, std::string_view shelf_id) {
  std::optional<size_t> from = IndexOf(id);
  if (!from || pins_[*from].shelf_id == shelf_id ||
      (!shelf_id.empty() && !FindShelf(shelf_id))) {
    return;
  }
  Pin pin = std::move(pins_[*from]);
  pins_.erase(pins_.begin() + *from);
  pin.shelf_id = std::string(shelf_id);
  pins_.insert(pins_.begin() + RangeOf(shelf_id).second, std::move(pin));
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

const Shelf* PinStore::FindShelf(std::string_view id) const {
  auto it = std::ranges::find(shelves_, id, &Shelf::id);
  return it != shelves_.end() ? &*it : nullptr;
}

std::string PinStore::AddShelf(const std::u16string& name) {
  Shelf shelf;
  shelf.id = base::Uuid::GenerateRandomV4().AsLowercaseString();
  shelf.name = name;
  shelves_.push_back(shelf);
  Changed();
  return shelf.id;
}

void PinStore::RenameShelf(std::string_view id, const std::u16string& name) {
  auto it = std::ranges::find(shelves_, id, &Shelf::id);
  if (it == shelves_.end() || it->name == name) {
    return;
  }
  it->name = name;
  Changed();
}

void PinStore::RemoveShelf(std::string_view id) {
  if (id.empty() || !FindShelf(id)) {
    return;
  }
  std::erase_if(pins_, [id](const Pin& pin) { return pin.shelf_id == id; });
  std::erase_if(shelves_, [id](const Shelf& shelf) { return shelf.id == id; });
  Changed();
}

void PinStore::AddObserver(Observer* observer) {
  observers_.AddObserver(observer);
}

void PinStore::RemoveObserver(Observer* observer) {
  observers_.RemoveObserver(observer);
}

void PinStore::Load() {
  for (const base::Value& value : profile_->GetPrefs()->GetList(kShelvesPref)) {
    const base::DictValue* dict = value.GetIfDict();
    const std::string* id = dict ? dict->FindString("id") : nullptr;
    if (!id || id->empty() || FindShelf(*id)) {
      continue;
    }
    Shelf shelf;
    shelf.id = *id;
    if (const std::string* name = dict->FindString("name")) {
      shelf.name = base::UTF8ToUTF16(*name);
    }
    shelves_.push_back(std::move(shelf));
  }
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
    const std::string* shelf_id = dict->FindString("shelf");
    if (shelf_id && !shelf_id->empty() && !FindShelf(*shelf_id)) {
      continue;
    }
    Pin pin;
    pin.id = *id;
    pin.shelf_id = shelf_id ? *shelf_id : std::string();
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
  // In the order RangeOf() expects, should the prefs not be.
  std::vector<std::string_view> order = {std::string_view()};
  for (const Shelf& shelf : shelves_) {
    order.push_back(shelf.id);
  }
  std::vector<Pin> loaded = std::exchange(pins_, {});
  for (std::string_view shelf_id : order) {
    for (Pin& pin : loaded) {
      if (pin.shelf_id == shelf_id) {
        pins_.push_back(std::move(pin));
      }
    }
  }
}

void PinStore::Changed() {
  base::ListValue list;
  for (const Pin& pin : pins_) {
    base::DictValue dict = base::DictValue()
                               .Set("id", pin.id)
                               .Set("url", pin.url.spec())
                               .Set("title", base::UTF16ToUTF8(pin.title))
                               .Set("icon", base::Base64Encode(pin.icon_png));
    if (!pin.shelf_id.empty()) {
      dict.Set("shelf", pin.shelf_id);
    }
    list.Append(std::move(dict));
  }
  profile_->GetPrefs()->SetList(kPinsPref, std::move(list));
  base::ListValue shelves;
  for (const Shelf& shelf : shelves_) {
    shelves.Append(base::DictValue()
                       .Set("id", shelf.id)
                       .Set("name", base::UTF16ToUTF8(shelf.name)));
  }
  profile_->GetPrefs()->SetList(kShelvesPref, std::move(shelves));
  observers_.Notify(&Observer::OnPinsChanged);
}

}  // namespace fiber
